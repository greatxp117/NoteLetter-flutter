import Foundation

/// INV-07's detection table — the one place a link becomes an `fn_ingest_url`
/// `type`. Mirrors web `detectUrlType()` in `api.js` (`spec/api/ingest.md`).
///
/// Compiled into the app AND the share extension, because the two used to
/// disagree: the extension guessed by `host.contains(…)` and knew no podcast,
/// and the app's Add Source sheet asked the reader to pick a type from a
/// segmented control that could not choose podcast either. A Spotify episode
/// filed as an `article` does not fail loudly — it files a web page.
enum URLContentType {
    /// Normalize, then detect (INV-07, 4.86.0, ADR-120 — `api/ingest.md`).
    /// An address bar shows `www.instagram.com/reel/…` with no scheme, which
    /// `URL(string:)` parses as a scheme-less path with no host, so a bare
    /// address was refused before the Instagram rule ran. Returns the string
    /// `fn_ingest_url` is sent — verbatim, never `URL.absoluteString` — or nil
    /// to reject locally. Only http(s), and the host must contain a dot;
    /// scheme and host are lower-cased, everything after them is untouched.
    /// Mirrors web `normalizeUrl()`; asserted by `URLDetectionTests` against
    /// `fixtures/url-detection/cases.json`.
    static func normalize(_ input: String) -> String? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return nil }
        let bare = matches(t, #"^[^\s/?#:]+\.[^\s/?#:]+(?::\d+)?(?:[/?#]\S*)?$"#)
        let hasScheme = matches(t, #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#) && !bare
        let candidate: String
        if hasScheme { candidate = t } else if bare { candidate = "https://" + t } else { return nil }
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".")
        else { return nil }
        // Scheme and host are case-insensitive, so they are lower-cased; the
        // path, query and fragment go through byte for byte.
        guard let sep = candidate.range(of: "://") else { return nil }
        let rest = candidate[sep.upperBound...]
        let authorityEnd = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        return candidate[..<sep.upperBound].lowercased()
            + rest[..<authorityEnd].lowercased()
            + rest[authorityEnd...]
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    /// Nil for anything `normalize` rejects, which is refused locally without
    /// calling the API. Hosts compare EXACTLY (lowercased, `www.` stripped):
    /// `contains` matched `notyoutube.com` and `instagram.com.example`.
    static func classify(_ string: String) -> String? {
        guard let normalized = normalize(string), let url = URL(string: normalized) else { return nil }
        return classify(url)
    }

    static func classify(_ url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        switch host {
        // 4.114.0 (ADR-151): a playlist page is a playlist — checked BEFORE
        // the video row. Only the path exactly `/playlist` with a non-empty
        // `list`: a `watch?v=…&list=…` link is the one video the reader
        // opened, and stays `youtube`. Until this row a pasted playlist was
        // sent as `youtube` and refused.
        case "youtube.com" where isPlaylistPage(url): return PlaylistAnswer.type
        case "youtube.com", "youtu.be": return "youtube"
        case "instagram.com": return "instagram"
        case "tiktok.com", "vm.tiktok.com": return "tiktok"
        case "podcasts.apple.com": return "podcast"
        case "open.spotify.com" where url.path.hasPrefix("/episode/"): return "podcast"
        default: return "article"
        }
    }

    /// The reference's `u.pathname === '/playlist' && u.searchParams.get('list')`.
    /// `URLComponents.path`, not `URL.path`: the latter strips a trailing
    /// slash, which would call `/playlist/` a playlist page the reference
    /// does not.
    private static func isPlaylistPage(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "/playlist" else { return false }
        let list = parts.queryItems?.first { $0.name == "list" }?.value ?? ""
        return !list.isEmpty
    }

    /// What the reader is told the link will be filed as, in place of the
    /// picker that used to ask them.
    static func label(_ type: String) -> String {
        switch type {
        case PlaylistAnswer.type: return PlaylistAnswer.label
        case "youtube": return "YouTube video"
        case "instagram": return "Instagram post"
        case "tiktok": return "TikTok video"
        case "podcast": return "Podcast episode"
        default: return "Article"
        }
    }
}
