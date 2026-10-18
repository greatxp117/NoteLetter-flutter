import Foundation
import Combine

struct UploadItem {
    let data: Data
    let filename: String
    let mimeType: String
}

@MainActor
final class UploadViewModel: ObservableObject {
    /// `fn_create_upload_session` → the signed PUT url, which every class but
    /// video uploads with.
    nonisolated static func uploadURL(from response: [String: Any]) -> String? {
        response["uploadUrl"] as? String
    }

    /// `fn_create_upload_session` → the resumable-session initiation url
    /// (4.14.0, ADR-050), which a VIDEO uploads with: up to 2 GB, where one
    /// PUT restarts from byte zero on any dropped connection.
    nonisolated static func resumableURL(from response: [String: Any]) -> String? {
        response["resumableUrl"] as? String
    }

    /// Which of the session's two shapes (INV-08) a file goes up in: the
    /// resumable session, for EVERY single file — web's rule (ADR-050) and the
    /// Flutter app's since F-121. A path that only runs for rare large files is
    /// a path nobody exercises. (The Swift app sent only video this way.)
    nonisolated static func usesResumableSession(mimeType: String) -> Bool {
        true
    }

    /// `fn_create_multi_image_session` → the set's id and one signed url per
    /// file, in the order sent — `nil` unless there is exactly one per file.
    nonisolated static func imageSetSession(from response: [String: Any], count: Int) -> (docId: String, uploadUrls: [String])? {
        guard let docId = response["docId"] as? String,
              let urls = response["uploadUrls"] as? [String],
              urls.count == count else { return nil }
        return (docId, urls)
    }

    @Published var isUploading = false
    @Published var errorMessage: String?

    func uploadSingleFile(_ item: UploadItem) async -> Bool {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let response = try await APIClient.call("fn_create_upload_session", method: .post, body: [
                "filename": item.filename,
                "mimeType": item.mimeType,
                "size": item.data.count
            ])
            if Self.usesResumableSession(mimeType: item.mimeType) {
                // No fallback to the single PUT if the session fails: that
                // would hide a broken session path behind small uploads that
                // work (ADR-050).
                guard let resumable = Self.resumableURL(from: response) else {
                    throw ApiError(message: "Missing resumable upload URL in response", status: nil, endpoint: "fn_create_upload_session", responseBody: response, errorCode: nil, requestId: nil)
                }
                try await ResumableUpload.upload(data: item.data, resumableURL: resumable, mimeType: item.mimeType)
            } else {
                guard let uploadUrl = Self.uploadURL(from: response) else {
                    throw ApiError(message: "Missing upload URL in response", status: nil, endpoint: "fn_create_upload_session", responseBody: response, errorCode: nil, requestId: nil)
                }
                try await UploadClient.putFile(data: item.data, to: uploadUrl, mimeType: item.mimeType)
            }
            // No `fn_signal_uploads_complete` here, deliberately: a single file
            // is picked up by the bucket's finalize trigger, and the signal is
            // the image SET's (api/uploads.md — 400 "Not an image set
            // document" for any other type). Web's single upload sends none.
            return true
        } catch let error as ApiError {
            errorMessage = error.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadImageSet(_ items: [UploadItem], title: String?) async -> Bool {
        guard !items.isEmpty, items.count <= 20 else {
            errorMessage = "Select between 1 and 20 images."
            return false
        }

        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            var body: [String: Any] = [
                "files": items.map { ["filename": $0.filename, "mimeType": $0.mimeType, "size": $0.data.count] }
            ]
            if let title, !title.isEmpty { body["title"] = title }

            let response = try await APIClient.call("fn_create_multi_image_session", method: .post, body: body)
            guard let (docId, uploadUrls) = Self.imageSetSession(from: response, count: items.count) else {
                throw ApiError(message: "Unexpected response from upload session", status: nil, endpoint: "fn_create_multi_image_session", responseBody: response, errorCode: nil, requestId: nil)
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, item) in items.enumerated() {
                    group.addTask {
                        try await UploadClient.putFile(data: item.data, to: uploadUrls[index], mimeType: item.mimeType)
                    }
                }
                for try await _ in group {}
            }

            _ = try await APIClient.call("fn_signal_uploads_complete", method: .post, body: ["docId": docId])
            return true
        } catch let error as ApiError {
            errorMessage = error.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// The answer, or nil when the request was refused (its sentence is in
    /// `errorMessage`). The answer is returned rather than a Bool because a
    /// playlist's `docIds` answer is said with its own measured count
    /// (`PlaylistAnswer`, 4.114.0) — a Bool threw that away, and every link
    /// read "Added link for processing." whatever the server had done.
    func ingestUrl(_ url: String, type: String) async -> [String: Any]? {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            return try await APIClient.call("fn_ingest_url", method: .post, body: ["url": url, "type": type])
        } catch let error as ApiError {
            errorMessage = error.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// What a link-add surface says when `fn_ingest_url` accepted the link:
    /// the playlist sentence for a `docIds` answer, the single link's own
    /// line otherwise.
    nonisolated static func linkAdded(_ answer: [String: Any]) -> String {
        PlaylistAnswer.sentence(answer) ?? "Added link for processing."
    }
}
