import Foundation

/// A YouTube playlist link (4.114.0, ADR-151 — `api/ingest.md` §A playlist
/// link). Mirrors web `shared/playlist.js` and Flutter `lib/shared/playlist.dart`.
///
/// `URLContentType` names a `youtube.com/playlist?list=…` link
/// `youtube_playlist`, and `fn_ingest_url` answers it with `docIds` — one
/// queued document per video — instead of one `docId`. That answer is ONE
/// success, stated with the measured count the server returned, and there is
/// no single document to open. `warnings` is never rendered: until 5.2.0 it
/// could carry yt-dlp's own text, and it still holds nothing a reader is owed.
///
/// Compiled into the app AND the share extension, the two link-add surfaces
/// that file a link: both said "Added link for processing." over every answer,
/// and neither could send the type at all until 4.114.0's row.
enum PlaylistAnswer {
    nonisolated static let type = "youtube_playlist"
    nonisolated static let label = "YouTube playlist"

    /// The sentence for a `docIds` answer, or nil for a single-document one.
    /// Counts are the answer's own fields (`enqueued`, `failed`,
    /// `notStarted`) — never `docIds.length` re-derived. A playlist longer
    /// than the server's cap says so, LAST, with the answer's own `cap`
    /// (5.2.0, ADR-160): "Added 100 videos" alone reads as the whole list.
    nonisolated static func sentence(_ answer: [String: Any]?) -> String? {
        guard let answer, answer["docIds"] is [Any],
              let enqueued = count(answer["enqueued"]) else { return nil }
        var parts = ["Added \(grouped(enqueued)) \(enqueued == 1 ? "video" : "videos") from this playlist."]
        if let failed = answer["failed"] as? [Any], !failed.isEmpty {
            parts.append("One could not be started — retry it from your library.")
        }
        if let notStarted = count(answer["notStarted"]), notStarted > 0 {
            parts.append(notStarted == 1
                ? "The 1 after it was not added."
                : "The \(grouped(notStarted)) after it were not added.")
        }
        if isTrue(answer["capped"]), let cap = count(answer["cap"]) {
            let c = grouped(cap)
            parts.append("The playlist has more than \(c) videos; only the first \(c) were read.")
        }
        return parts.joined(separator: " ")
    }

    /// A JSON number, and only a number: `JSONSerialization` hands a `true`
    /// back as an `NSNumber` too, which `as? Int` would read as 1.
    nonisolated private static func count(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, !isBoolean(n), n.doubleValue.isFinite else { return nil }
        return n.intValue
    }

    /// The reference's `res.capped === true` — a JSON `true`, not a 1.
    nonisolated private static func isTrue(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber, isBoolean(n) else { return false }
        return n.boolValue
    }

    nonisolated private static func isBoolean(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    /// `toLocaleString()` for a count, as the reference groups it.
    nonisolated private static func grouped(_ n: Int) -> String { n.formatted() }
}
