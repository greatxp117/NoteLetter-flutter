// tool/share_body_check.sh — the stand-in APIClient for a plain swiftc build.

import Foundation

// The Share extension's APIClient talks to Firebase Auth; this check stands
// in for it on the Mac: it records each body and refuses, so nothing reaches
// the network and the caller's catch runs.
enum HTTPMethod: String { case get = "GET", post = "POST" }

struct ApiError: Error, LocalizedError {
    let message: String
    let status: Int?
    let endpoint: String
    let responseBody: [String: Any]?
    let errorCode: String?
    let requestId: String?
    var errorDescription: String? { message }
}

enum APIClient {
    nonisolated(unsafe) static var sent: [(path: String, body: [String: Any])] = []
    static func call(_ path: String, method: HTTPMethod = .get, body: [String: Any]? = nil) async throws -> [String: Any] {
        sent.append((path, body ?? [:]))
        throw ApiError(message: "refused by the check", status: 400, endpoint: path, responseBody: nil, errorCode: nil, requestId: nil)
    }
}
