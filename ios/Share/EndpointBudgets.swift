import Foundation

/// **Each endpoint's DEPLOYED deadline, in seconds** (D3 — C5's twin, which
/// Flutter closed in `lib/services/endpoint_budgets.dart`).
///
/// `APIClient` sent every request through `URLSession.shared` and never touched
/// `timeoutInterval`, so every `fn_*` this client calls waited the URL
/// loading system's default of **60 seconds** — a number chosen by Foundation,
/// about a fleet it has never heard of. Two of the sixteen endpoints here
/// deploy above it: `fn_generate_audio` at 120s and `fn_synthesize_search` at
/// **300s**. A long TTS therefore showed "The request timed out." while the
/// audio was still being written, and the Retry beside it paid for the whole
/// synthesis a second time; a cohesive search was cut at a fifth of the time
/// the backend is allowed to take.
///
/// A timeout the client sets must be ABOVE the deadline it is waiting on, not
/// below: the server's own deadline is what produces a real answer, and a
/// client that gives up first converts an answer into a fabricated failure.
/// That is INV-26/ADR-102 read from the other end — there the rule is that an
/// upstream call must be bounded BELOW the deadline hosting it.
///
/// These are the values in each `fn_*`'s own deploy recipe in `main.py`, which
/// `deploy_check.py` already compares to the live revision — so this is a
/// mirror of a fact checked at its source, not a second opinion about it.
/// `client_timeout_check.py --target ios` compares the two both ways, because
/// a hand-copied table is a table that drifts, and it is the recipes that move.
enum EndpointBudgets {
    /// Twenty-two, not Flutter's sixty: this client's surface is its own, and the
    /// gate's UNCALLED direction is what keeps the table from quietly becoming
    /// a copy of another client's.
    static let deadlineSeconds: [String: Int] = [
        "fn_create_capture_session": 60,
        "fn_create_multi_image_session": 60,
        "fn_create_upload_session": 60,
        "fn_delete_document": 60,
        "fn_generate_audio": 120,
        "fn_get_raw_document_url": 60,
        "fn_ingest_url": 60,
        "fn_mark_support_read": 60,
        "fn_newsletter_settings": 60,
        "fn_plan_status": 60,
        "fn_notification_channels": 60,
        "fn_register_device": 60,
        "fn_request_newsletter": 60,
        "fn_retry_document": 60,
        "fn_search_notes": 60,
        "fn_send_support_message": 60,
        "fn_signal_uploads_complete": 60,
        "fn_synthesize_search": 300,
        "fn_unregister_device": 60,
        "fn_update_content": 60,
        "fn_update_document": 60,
        "fn_update_from_source": 300,
    ]

    /// What the client waits on top of the server's own deadline: the request
    /// has to cross the network twice and may wake a cold instance, and a
    /// margin of zero would race the very deadline it is meant to outlast.
    static let marginSeconds = 15

    /// The fallback for a path with no entry. 60s is the fleet norm, so an
    /// endpoint added without being listed still gets the common deadline —
    /// and the gate fails on the omission, so the default is a floor rather
    /// than a way of not deciding.
    static let defaultTimeout: TimeInterval = 60 + 15

    /// The budget for one request path (`fn_foo`, with or without a query).
    static func timeout(for path: String) -> TimeInterval {
        let name = path
            .split(separator: "?", maxSplits: 1).first
            .map(String.init)?
            .split(separator: "/")
            .first
            .map(String.init)
        guard let name, let seconds = deadlineSeconds[name] else {
            return defaultTimeout
        }
        return TimeInterval(seconds + marginSeconds)
    }
}
