import Foundation
import FirebaseAuth

struct ApiError: Error, LocalizedError {
    let message: String
    let status: Int?
    let endpoint: String
    let responseBody: [String: Any]?
    let errorCode: String?
    let requestId: String?

    var errorDescription: String? { message }

    /// A cooldown's wait as a number (4.107.0, ADR-140): `retry_after_s` on
    /// our envelope, present on every cooldown refusal and on nothing else —
    /// which is what tells "wait" from the cap's "stop" (both are 429
    /// `RATE_LIMITED`). Read from the envelope only; never parsed out of the
    /// sentence, four of whose nine spellings carry no figure at all.
    var retryAfterS: Int? { Self.retryAfterSeconds(responseBody) }

    /// `retry_after_s` from an envelope, or nil. Only a positive whole number
    /// counts — absent, a string, zero, a fraction, a boolean, or a body that
    /// is not our envelope is no number, never a guess. Web's
    /// `retryAfterSeconds`, one rule: JSON has one number type, so `43.0` is
    /// the integer 43 there and is here.
    nonisolated static func retryAfterSeconds(_ body: [String: Any]?) -> Int? {
        guard let n = body?["retry_after_s"] as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d >= 1, d == d.rounded(), d <= Double(Int32.max) else { return nil }
        return Int(d)
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Mirrors NoteLetter-web's src/api.js `call()` helper: injects the Firebase
/// ID token, hits the Cloud Functions base URL, and surfaces structured errors.
enum APIClient {
    /// Prod, unless a DEBUG build was launched with `USE_EMULATOR=true` or is
    /// a unit-test host ([EmulatorConfig.routesToEmulator]). Computed rather
    /// than stored: a `static let` is resolved once at first touch, which on a
    /// test host can be before the environment has been read.
    static var base: String {
        EmulatorConfig.routesToEmulator
            ? EmulatorConfig.functionsBase
            : "https://us-central1-noteletter-7a111.cloudfunctions.net"
    }

    /// Resolves the Firebase ID token for INV-01. Defaults to the signed-in
    /// user; swappable in the conformance harness, which is the only way this
    /// client's RESPONSE handling can be exercised at all — every path below
    /// sits behind a live Firebase session otherwise, which is why ADR-112's
    /// iOS half had no test until the seam existed. Mirrors the web
    /// reference's mocked auth and Flutter's `tokenProvider` (C4g).
    ///
    /// Returning nil means "nobody is signed in"; throwing means the token
    /// could not be minted. They are different failures and say so.
    static var tokenProvider: () async throws -> String? = defaultTokenProvider

    static let defaultTokenProvider: () async throws -> String? = {
        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDToken()
    }

    /// Put the real provider back. A seam that cannot be un-set leaves a test's
    /// transport installed for everything that runs after it in the same
    /// process — the shape `test_isolation_test` refuses on Flutter.
    static func resetTestSeams() {
        tokenProvider = defaultTokenProvider
    }

    static func call(_ path: String, method: HTTPMethod = .get, body: [String: Any]? = nil) async throws -> [String: Any] {
        let endpoint = "\(base)/\(path)"

        var resolved: String?
        do {
            resolved = try await tokenProvider()
        } catch {
            throw ApiError(message: "Failed to get auth token: \(error.localizedDescription)", status: nil, endpoint: endpoint, responseBody: nil, errorCode: nil, requestId: nil)
        }
        guard let token = resolved else {
            throw ApiError(message: "Not signed in.", status: nil, endpoint: endpoint, responseBody: nil, errorCode: nil, requestId: nil)
        }

        guard let url = URL(string: endpoint) else {
            throw ApiError(message: "Invalid URL", status: nil, endpoint: endpoint, responseBody: nil, errorCode: nil, requestId: nil)
        }

        // The deadline this endpoint is DEPLOYED with, plus a margin — not
        // Foundation's 60s default, which is a number chosen about a fleet it
        // has never heard of and is below two of this client's endpoints
        // (D3). `URLRequest.timeoutInterval` is what the URL loading system
        // reads; the session is shared, so it is set per request and not on a
        // configuration.
        var request = URLRequest(url: url, timeoutInterval: EndpointBudgets.timeout(for: path))
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ApiError(message: "Network error: \(error.localizedDescription)", status: nil, endpoint: endpoint, responseBody: nil, errorCode: nil, requestId: nil)
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        // `api/endpoints.md` §A body that is NOT this envelope (ADR-112). A
        // Cloud Run or load-balancer 504 is an HTML page and a dead container
        // sends nothing, so this branch runs often — and it used to render
        // `HTTP 504`: the status, as a string, as the reader's sentence. The
        // words are the contract's, the same in all four clients, gated by
        // NON-ENVELOPE.
        let status = (response as? HTTPURLResponse)?.statusCode
        let noEnvelope = "The server did not answer as expected (HTTP \(status ?? 0))."

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // A plan refusal (4.79.0, ADR-113) is the one rejection another
            // screen draws a consequence of: the Settings Plan row refetches
            // its MEASURED figures on this signal rather than counting
            // anything itself (§12). Posted here, at the one place every
            // verb's failure passes through — the reference dispatches
            // `nl-plan-limit` from its single `call()` seam for the same
            // reason. It carries no payload on purpose: the event says the
            // figures you hold are stale, never what the new ones are.
            if (json?["error_code"] as? String) == "PLAN_LIMIT" {
                NotificationCenter.default.post(name: .planLimitRefused, object: nil)
            }
            throw ApiError(
                message: (json?["error"] as? String) ?? (json?["message"] as? String) ?? noEnvelope,
                status: status,
                endpoint: endpoint,
                responseBody: json,
                errorCode: json?["error_code"] as? String,
                requestId: json?["request_id"] as? String
            )
        }
        // A 2xx we could not read is a failure, not an empty answer. This was
        // `json ?? [:]`, and every caller treats an empty dictionary as
        // success: a decode that found nothing became a document with no
        // fields, a list with no rows, a settings read that answered "all
        // defaults". `fn_*` answers JSON on every success path, so this is a
        // proxy, a truncation, or a deploy serving something else.
        guard let json else {
            throw ApiError(message: noEnvelope, status: http.statusCode, endpoint: endpoint,
                           responseBody: nil, errorCode: nil, requestId: nil)
        }
        return json
    }
}

extension Notification.Name {
    /// Fired by ``APIClient/call(_:method:body:)`` on any `PLAN_LIMIT`, from
    /// any verb (4.79.0, ADR-113, INV-28).
    static let planLimitRefused = Notification.Name("nl-plan-limit")
}
