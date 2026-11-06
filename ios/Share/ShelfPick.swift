import Foundation

// Kit §20.1's rules and the tags read's shapes, pure, so `RunnerTests` compiles
// this file and asserts them (ShelfPickTests). The rules are
// `lib/shared/shelf_pick.dart` and `lib/shared/shelf_tree.dart`, rule for rule:
// the ranking is normative, and a search that orders differently here would be
// a different app from the one this extension shares a phone with.

/// One of the reader's shelves, as the tags read delivered it.
struct Shelf: Identifiable, Equatable {
    let id: String
    let title: String
    let color: String?
    /// nil when no count was ever stored: an unread count is not zero (ADR-109).
    let documentCount: Int?
    /// A stored id is a claim. `ShelfTree` resolves it, and a dangling one reads
    /// as top-level.
    let parentId: String?
}

// MARK: - The shelf tree (5.28.0, ADR-185, INV-33)

struct ShelfTree {
    static let hops = 64
    static let pathSeparator = " › "

    let byId: [String: Shelf]
    /// A shelf with no entry is top-level.
    let parent: [String: String]
    let roots: [Shelf]
    private let children: [String: [Shelf]]

    init(_ shelves: [Shelf]) {
        var byId: [String: Shelf] = [:]
        for s in shelves { byId[s.id] = s }
        let known = byId

        func raw(_ id: String) -> String? {
            guard let p = known[id]?.parentId, p != id, known[p] != nil else { return nil }
            return p
        }

        var parent: [String: String] = [:]
        for s in shelves {
            var p = raw(s.id)
            var cur = p
            var seen: Set<String> = [s.id]
            var hops = 1
            while let c = cur {
                if c == s.id || hops > Self.hops {
                    p = nil // on a cycle, or too deep
                    break
                }
                if seen.contains(c) { break } // a cycle above, not through s
                seen.insert(c)
                cur = raw(c)
                hops += 1
            }
            if let p { parent[s.id] = p }
        }

        // Children keep the read's order, which is the rail's.
        var children: [String: [Shelf]] = [:]
        var roots: [Shelf] = []
        for s in shelves {
            if let p = parent[s.id] {
                children[p, default: []].append(s)
            } else {
                roots.append(s)
            }
        }
        self.byId = known
        self.parent = parent
        self.children = children
        self.roots = roots
    }

    /// Nearest first.
    func ancestors(_ id: String) -> [Shelf] {
        var out: [Shelf] = []
        var cur = parent[id]
        while let c = cur, let s = byId[c] {
            out.append(s)
            cur = parent[c]
        }
        return out
    }

    /// Depth first, siblings in the read's order: what the picker lists.
    func ordered() -> [Shelf] {
        var out: [Shelf] = []
        func walk(_ s: Shelf) {
            out.append(s)
            for c in children[s.id] ?? [] { walk(c) }
        }
        for r in roots { walk(r) }
        return out
    }

    func pathLabel(_ id: String) -> String {
        ancestors(id).reversed()
            .map { $0.title.isEmpty ? "Untitled" : $0.title }
            .joined(separator: Self.pathSeparator)
    }
}

// MARK: - §20.1 Matching (4.104.0, ADR-137)

enum ShelfPick {
    /// What the four endpoints take (`_CHOSEN_SHELVES_MAX`). An eleventh is held
    /// by §20.3's row rather than refused there.
    static let maxAtAdd = 10

    /// Letters NFD does not take apart, as `shelf_pick.dart` folds them.
    private static let plain: [String: String] = [
        "ø": "o", "ß": "ss", "æ": "ae", "œ": "oe", "ł": "l",
    ]

    /// A title folded for matching, with `map[i]` the place in the ORIGINAL title
    /// of folded scalar i, so a run drawn from a folded match lands on the
    /// characters the reader typed against.
    struct Folded {
        let scalars: [Unicode.Scalar]
        let map: [String.Index]
    }

    static func fold(_ s: String) -> Folded {
        var out: [Unicode.Scalar] = []
        var map: [String.Index] = []
        let view = s.unicodeScalars
        var i = view.startIndex
        while i != view.endIndex {
            let lower = String(Character(view[i])).lowercased()
            let folded = plain[lower] ?? lower.decomposedStringWithCanonicalMapping
            for v in folded.unicodeScalars where !(0x0300...0x036F).contains(v.value) {
                out.append(v)
                map.append(i)
            }
            i = view.index(after: i)
        }
        map.append(view.endIndex)
        return Folded(scalars: out, map: map)
    }

    private static func trimmed(_ q: String) -> String {
        q.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func foldQuery(_ q: String) -> [Unicode.Scalar] {
        fold(trimmed(q)).scalars
    }

    /// Where a query matched a title. `rank` 0: the title starts with it; 1: a
    /// word in it does; 2: it is anywhere inside. `run` is nil for an empty query.
    struct Match: Equatable {
        let rank: Int
        let run: Range<String.Index>?
    }

    private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func firstIndex(of needle: [Unicode.Scalar], in hay: [Unicode.Scalar], from: Int) -> Int? {
        guard hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        var p = from
        while p <= hay.count - needle.count {
            if Array(hay[p..<(p + needle.count)]) == needle { return p }
            p += 1
        }
        return nil
    }

    static func match(_ title: String, _ q: String) -> Match? {
        let needle = foldQuery(q)
        if needle.isEmpty { return Match(rank: 0, run: nil) }
        let f = fold(title)
        guard let any = firstIndex(of: needle, in: f.scalars, from: 0) else { return nil }
        // The first occurrence that begins a word is the one to rank and draw.
        var word = -1
        var next: Int? = any
        while let p = next {
            if p == 0 || !isWordScalar(f.scalars[p - 1]) {
                word = p
                break
            }
            next = firstIndex(of: needle, in: f.scalars, from: p + 1)
        }
        let at = word == -1 ? any : word
        let rank = word == 0 ? 0 : (word > 0 ? 1 : 2)
        return Match(rank: rank, run: f.map[at]..<f.map[at + needle.count])
    }

    struct Row: Equatable {
        let shelf: Shelf
        let match: Match
    }

    /// The rows the picker lists, filtered and ranked. Equal ranks keep the order
    /// they arrived in, so the list never reshuffles among equals.
    static func rows(_ addable: [Shelf], _ q: String) -> [Row] {
        var found: [(row: Row, at: Int)] = []
        for (i, s) in addable.enumerated() {
            if let m = match(s.title, q) { found.append((Row(shelf: s, match: m), i)) }
        }
        found.sort { a, b in
            a.row.match.rank != b.row.match.rank
                ? a.row.match.rank < b.row.match.rank
                : a.at < b.at
        }
        return found.map(\.row)
    }

    /// What the create row offers and what an empty list says. `createName` is the
    /// name *Create "…"* offers, or empty for *New shelf…*; `empty` is the sentence
    /// for an empty list, or nil when rows exist.
    struct State: Equatable {
        let createName: String
        let empty: String?
    }

    static func state(onItem: [Shelf], addable: [Shelf], q: String, rows: [Row]) -> State {
        let name = trimmed(q)
        let needle = foldQuery(name)
        let here = needle.isEmpty ? nil : onItem.first { foldQuery($0.title) == needle }
        let exists = here != nil
            || (!needle.isEmpty && addable.contains { foldQuery($0.title) == needle })
        var empty: String?
        if rows.isEmpty {
            if let here {
                empty = "“\(here.title)” is already here."
            } else if !needle.isEmpty {
                empty = "No shelf matches “\(name)”."
            } else if !onItem.isEmpty {
                empty = "Every shelf is already here."
            } else {
                empty = "No shelves yet."
            }
        }
        return State(createName: exists ? "" : name, empty: empty)
    }

    /// What pressing row `i` chooses, or nil when there is nothing there: a picker
    /// with no rows and no create row (a read that failed, or has not landed) has
    /// no active row, and Return on it must choose nothing.
    enum Choice: Equatable {
        case none
        case shelf(String)
        case create(String)
    }

    static func choice(at i: Int, lead: Int, rows: [Row], state: State, creates: Bool) -> Choice? {
        if i < lead { return Choice.none }
        if i < lead + rows.count { return .shelf(rows[i - lead].shelf.id) }
        return creates ? .create(state.createName) : nil
    }
}

// MARK: - The tags read, over Firestore REST (share-sheet.md §Endpoints used)

enum ShelfRead {
    /// `tags where user_id == uid`, in the subscription's order: the app's own
    /// query, and the composite index it already needs. No limit, as the app's has
    /// none: a list that stopped short would read as shelves the reader does not
    /// have. Only the fields the sheet draws: a tag also carries its embedding, and
    /// an extension's memory ceiling is a fraction of the app's.
    static func query(uid: String) -> [String: Any] {
        [
            "structuredQuery": [
                "from": [["collectionId": "tags"]],
                "select": ["fields": ["title", "color", "document_count", "parent_tag_id", "status"]
                    .map { ["fieldPath": $0] }],
                "where": ["fieldFilter": [
                    "field": ["fieldPath": "user_id"],
                    "op": "EQUAL",
                    "value": ["stringValue": uid],
                ]],
                "orderBy": [["field": ["fieldPath": "created_at"], "direction": "DESCENDING"]],
            ] as [String: Any],
        ]
    }

    /// The shelves in a `:runQuery` answer, less any being deleted, or nil when it
    /// is not an answer. A failed read must never reach the picker as an empty
    /// list (kit §20.3): a row can carry an `error` under a 200, the stream's way
    /// of failing part way, and a reader with no shelves still gets one row with
    /// a `readTime` and no `document`.
    static func shelves(from answer: Any?) -> [Shelf]? {
        guard let rows = answer as? [[String: Any]] else { return nil }
        var out: [Shelf] = []
        for row in rows {
            if row["error"] != nil { return nil }
            guard let doc = row["document"] as? [String: Any],
                  let name = doc["name"] as? String,
                  let id = name.split(separator: "/").last.map(String.init) else { continue }
            let fields = doc["fields"] as? [String: Any] ?? [:]
            func string(_ key: String) -> String? {
                (fields[key] as? [String: Any])?["stringValue"] as? String
            }
            if string("status") == "deleting" { continue }
            let parent = string("parent_tag_id")
            out.append(Shelf(
                id: id,
                title: string("title") ?? "",
                color: string("color"),
                documentCount: count(fields["document_count"]),
                parentId: parent?.isEmpty == true ? nil : parent
            ))
        }
        return out
    }

    /// REST writes an integer as a string, and a double as a number.
    private static func count(_ value: Any?) -> Int? {
        guard let field = value as? [String: Any] else { return nil }
        if let s = field["integerValue"] as? String { return Int(s) }
        if let d = field["doubleValue"] as? NSNumber, d.doubleValue.isFinite { return d.intValue }
        return nil
    }

    /// A request body with the reader's shelves on it, or no key at all with none
    /// chosen, so a plain add is byte for byte what it was (5.73.0, ADR-238).
    static func adding(_ tagIds: [String], to body: [String: Any]) -> [String: Any] {
        guard !tagIds.isEmpty else { return body }
        var out = body
        out["tagIds"] = tagIds
        return out
    }
}
