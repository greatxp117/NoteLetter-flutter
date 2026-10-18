import Foundation

/// Raw file upload to GCS signed URLs — bypasses APIClient (no JSON body, no auth header).
enum UploadClient {
    static func putFile(data: Data, to signedURL: String, mimeType: String) async throws {
        guard let url = URL(string: signedURL) else {
            throw ApiError(message: "Invalid upload URL", status: nil, endpoint: signedURL, responseBody: nil, errorCode: nil, requestId: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        // Body is supplied via `upload(for:from:)` below — do not also set httpBody,
        // or URLSession warns and may ignore one of them.

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.upload(for: request, from: data)
        } catch {
            throw ApiError(message: "Upload failed: \(error.localizedDescription)", status: nil, endpoint: signedURL, responseBody: nil, errorCode: nil, requestId: nil)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw ApiError(message: "Upload failed with status \(status ?? 0)", status: status, endpoint: signedURL, responseBody: nil, errorCode: nil, requestId: nil)
        }
    }
}
