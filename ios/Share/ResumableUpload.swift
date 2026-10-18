import Foundation

/// A GCS resumable session (INV-08's second shape, 4.14.0 / ADR-050), for the
/// upload a single PUT cannot carry: a video, capped at 2 GB, whose one PUT
/// restarts from byte zero on any dropped connection. Mirrors web
/// `uploadResumable` (`src/api.js`) step for step.
///
/// **What the session says it holds is the only authority.** The offset to
/// resume from is ASKED (`bytes */total`) after every failure, never inferred
/// from what this client believes it sent: a chunk can be in flight, partly
/// received or refused, and resuming from a wrong offset finalizes an object
/// that is the wrong bytes and still chunks, embeds and stores `complete`.
///
/// No fallback to the bare PUT on failure: a fallback would make a broken
/// session path invisible — small uploads working, large ones failing
/// irreproducibly. Unlike web, the session URI is not kept across launches:
/// a resumed launch starts a new session (GCS keeps the old one ~7 days and
/// it is simply abandoned). `Networking/UploadClient` and the share extension
/// keep the single PUT.
enum ResumableUpload {
    static let chunkMultiple = 256 * 1024          // GCS requires this granularity
    static let chunkMax = 8 * 1024 * 1024
    static let chunkTargetCount = 50               // ~50 committed progress steps
    static let maxAttempts = 5

    /// A multiple of 256 KiB, between 256 KiB and 8 MiB, aiming at ~50 chunks.
    static func chunkSize(for total: Int) -> Int {
        let target = Int((Double(total) / Double(chunkTargetCount) / Double(chunkMultiple)).rounded(.up)) * chunkMultiple
        return min(chunkMax, max(chunkMultiple, target == 0 ? chunkMultiple : target))
    }

    /// The `Range` a 308 carries (`bytes=0-8388607`) → the next offset. Nil
    /// when absent: nothing committed yet.
    static func nextOffset(fromRange range: String?) -> Int? {
        guard let range, let last = range.split(separator: "-").last, let end = Int(last) else { return nil }
        return end + 1
    }

    /// Backoff before attempt `n` (1-based): 0.5s, 1s, 2s, 4s.
    static var backoff: (Int) -> UInt64 = { n in UInt64(500_000_000) << UInt64(max(0, n - 1)) }

    static func upload(data: Data, resumableURL: String, mimeType: String,
                       session: URLSession = .shared,
                       onProgress: ((Double) -> Void)? = nil) async throws {
        let total = data.count
        let report = { (bytes: Int) in onProgress?(total == 0 ? 1 : Double(bytes) / Double(total)) }
        let uri = try await initiate(resumableURL, mimeType: mimeType, session: session)

        // A zero-byte file has no chunk to send; the status query finalizes it.
        var offset = try await committed(uri, total: total, session: session)
        report(offset)
        if total == 0 || offset >= total { return }

        let chunk = chunkSize(for: total)
        // ONE retry budget for the whole upload, reset whenever real progress
        // is committed — per chunk, a failing connection would retry forever.
        var attempt = 0
        while offset < total {
            let end = min(offset + chunk, total)
            var req = URLRequest(url: uri)
            req.httpMethod = "PUT"
            req.setValue("bytes \(offset)-\(end - 1)/\(total)", forHTTPHeaderField: "Content-Range")
            req.httpBody = data.subdata(in: offset..<end)

            let status: Int, rangeHeader: String?
            do {
                let (_, res) = try await session.data(for: req)
                let http = res as? HTTPURLResponse
                status = http?.statusCode ?? 0
                rangeHeader = http?.value(forHTTPHeaderField: "Range")
            } catch {
                // A dropped connection is the case this exists for: ask the
                // session what it kept, and go on from there.
                attempt += 1
                if attempt >= maxAttempts { throw failure("Upload failed: \(error.localizedDescription)", uri) }
                try await Task.sleep(nanoseconds: backoff(attempt))
                offset = try await committed(uri, total: total, session: session)
                report(offset)
                continue
            }

            switch status {
            case 200, 201:
                offset = total
            case 308:
                // No Range means the session kept NOTHING (GCS: "no bytes have
                // been persisted"), never "it kept this chunk" — which would
                // skip the chunk and finalize an object with a hole. Same rule
                // as the Flutter app (lib/services/resumable_upload.dart).
                let next = nextOffset(fromRange: rangeHeader) ?? 0
                // A session that reports no forward movement would otherwise
                // be sent the same chunk forever and look like a stall.
                if next <= offset {
                    attempt += 1
                    if attempt >= maxAttempts { throw failure("Upload failed: the session stopped accepting data.", uri) }
                } else {
                    attempt = 0
                }
                offset = next
                report(offset)
            case 500...:
                attempt += 1
                if attempt >= maxAttempts { throw failure("Upload failed: HTTP \(status)", uri, status) }
                try await Task.sleep(nanoseconds: backoff(attempt))
            default:
                // 4xx: the session is gone or the range was refused. Never
                // loop on it.
                throw failure("Upload failed: HTTP \(status)", uri, status)
            }
        }
        report(total)
    }

    /// Open the session; its URI comes back in `Location`.
    private static func initiate(_ resumableURL: String, mimeType: String, session: URLSession) async throws -> URL {
        guard let url = URL(string: resumableURL) else { throw failure("Invalid upload URL", nil) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // Signed into the URL by fn_create_upload_session, so it must be sent
        // exactly — it is what makes this POST a session start.
        req.setValue("start", forHTTPHeaderField: "x-goog-resumable")
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (_, res) = try await session.data(for: req)
        let http = res as? HTTPURLResponse
        guard let status = http?.statusCode, status == 200 || status == 201 else {
            throw failure("Upload could not start: HTTP \(http?.statusCode ?? 0)", url, http?.statusCode)
        }
        guard let location = http?.value(forHTTPHeaderField: "Location"), let uri = URL(string: location) else {
            throw failure("Upload could not start: the storage session returned no Location.", url, status)
        }
        return uri
    }

    /// Ask the session how much it has COMMITTED → the next byte offset.
    private static func committed(_ uri: URL, total: Int, session: URLSession) async throws -> Int {
        var req = URLRequest(url: uri)
        req.httpMethod = "PUT"
        req.setValue("bytes */\(total)", forHTTPHeaderField: "Content-Range")
        let (_, res) = try await session.data(for: req)
        let http = res as? HTTPURLResponse
        switch http?.statusCode {
        case 200, 201: return total
        case 308: return nextOffset(fromRange: http?.value(forHTTPHeaderField: "Range")) ?? 0
        default:
            throw failure("Upload could not resume: HTTP \(http?.statusCode ?? 0)", uri, http?.statusCode)
        }
    }

    private static func failure(_ message: String, _ url: URL?, _ status: Int? = nil) -> ApiError {
        ApiError(message: message, status: status, endpoint: url?.absoluteString ?? "resumable-upload",
                 responseBody: nil, errorCode: nil, requestId: nil)
    }
}
