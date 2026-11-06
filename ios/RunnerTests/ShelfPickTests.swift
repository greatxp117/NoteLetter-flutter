import XCTest
// F-172: `ShelfPick.swift` is compiled into this bundle from ios/Share, as
// `UploadTypes.swift` is, so what these read is the extension's own rule.

/// Kit §20.1's matching, the shelf tree and the tags read's shapes, over the
/// cases `test/kit/shelf_picker_test.dart` and `test/contract/shelf_tree_test.dart`
/// hold for the app: the ranking is normative, so the two must not disagree.
final class ShelfPickTests: XCTestCase {
    private func s(_ id: String, _ title: String, parent: String? = nil, count: Int? = 0) -> Shelf {
        Shelf(id: id, title: title, color: "sage-500", documentCount: count, parentId: parent)
    }

    private func run(_ title: String, _ q: String) -> String? {
        guard let m = ShelfPick.match(title, q), let run = m.run else { return nil }
        return String(title[run])
    }

    // MARK: Matching

    func testFoldsCaseAndAccents() {
        XCTAssertEqual(ShelfPick.fold("Café Ärzte").scalars.map(String.init).joined(), "cafe arzte")
        XCTAssertEqual(ShelfPick.fold("Straße").scalars.map(String.init).joined(), "strasse")
    }

    func testRanksATitleStartThenAWordStartThenAnywhere() {
        let rows = ShelfPick.rows([s("1", "Pasta"), s("2", "Post-war Studies"), s("3", "Stories")], "st")
        XCTAssertEqual(rows.map(\.shelf.title), ["Stories", "Post-war Studies", "Pasta"])
        XCTAssertEqual(rows.map(\.match.rank), [0, 1, 2])
    }

    func testDrawsTheRunItRankedNotTheFirstOccurrence() {
        XCTAssertEqual(run("Post-war Studies", "st"), "St")
    }

    func testHighlightsTheAccentedCharactersAFoldedQueryMatched() {
        XCTAssertEqual(run("Notes au café", "CAFE"), "café")
        // The same letter written as e + a combining accent keeps its accent.
        XCTAssertEqual(run("Notes au cafe\u{0301}", "cafe"), "cafe\u{0301}")
        XCTAssertEqual(run("Straße", "ss"), "ß")
    }

    func testEqualsKeepTheirOrderAndAnEmptyQueryListsEverything() {
        let rows = ShelfPick.rows([s("1", "Pasta"), s("2", "Stories"), s("4", "Finance")], "  ")
        XCTAssertEqual(rows.map(\.shelf.id), ["1", "2", "4"])
        XCTAssertNil(rows[0].match.run)
    }

    func testNoMatchIsNoRow() {
        XCTAssertNil(ShelfPick.match("Pasta", "xyz"))
    }

    // MARK: The create row and the empty line

    private func state(_ onItem: [Shelf], _ addable: [Shelf], _ q: String) -> ShelfPick.State {
        ShelfPick.state(onItem: onItem, addable: addable, q: q, rows: ShelfPick.rows(addable, q))
    }

    func testOffersToCreateTheQueryWhenNoShelfIsNamedByIt() {
        let st = state([], [s("1", "Pasta")], " Tax records ")
        XCTAssertEqual(st.createName, "Tax records")
        XCTAssertEqual(st.empty, "No shelf matches “Tax records”.")
    }

    func testNeverOffersASecondShelfWithANameThatExists() {
        XCTAssertEqual(state([], [s("1", "Pasta")], "pasta").createName, "")
        let here = state([s("4", "Finance")], [s("1", "Pasta")], "FINANCE")
        XCTAssertEqual(here.createName, "")
        XCTAssertEqual(here.empty, "“Finance” is already here.")
    }

    func testTheEmptySentences() {
        XCTAssertEqual(state([], [], "").empty, "No shelves yet.")
        XCTAssertEqual(state([s("1", "Pasta")], [], "").empty, "Every shelf is already here.")
        XCTAssertNil(state([], [s("1", "Pasta")], "").empty)
    }

    // MARK: What a press chooses

    func testAnEmptyPickerWithNoCreateRowChoosesNothingOnReturn() {
        let empty = ShelfPick.State(createName: "", empty: nil)
        XCTAssertNil(ShelfPick.choice(at: 0, lead: 0, rows: [], state: empty, creates: false))
    }

    func testAPressChoosesTheNoneRowTheShelfOrTheCreateRow() {
        let rows = ShelfPick.rows([s("1", "Pasta")], "")
        let st = ShelfPick.State(createName: "Tax", empty: nil)
        XCTAssertEqual(ShelfPick.choice(at: 0, lead: 1, rows: rows, state: st, creates: false), ShelfPick.Choice.none)
        XCTAssertEqual(ShelfPick.choice(at: 1, lead: 1, rows: rows, state: st, creates: false), .shelf("1"))
        XCTAssertNil(ShelfPick.choice(at: 2, lead: 1, rows: rows, state: st, creates: false))
        XCTAssertEqual(ShelfPick.choice(at: 1, lead: 0, rows: rows, state: st, creates: true), .create("Tax"))
    }

    func testTheCapIsWhatTheEndpointsTake() {
        XCTAssertEqual(ShelfPick.maxAtAdd, 10)
    }

    // MARK: The tree

    func testTreeOrderIsDepthFirstWithSiblingsAsRead() {
        let tree = ShelfTree([s("c", "Child", parent: "p"), s("q", "Other"), s("p", "Parent")])
        XCTAssertEqual(tree.ordered().map(\.id), ["q", "p", "c"])
        XCTAssertEqual(tree.pathLabel("c"), "Parent")
    }

    func testADanglingParentIsTopLevelAndACycleIsBroken() {
        let dangling = ShelfTree([s("a", "A", parent: "gone")])
        XCTAssertEqual(dangling.roots.map(\.id), ["a"])
        let cycle = ShelfTree([s("a", "A", parent: "b"), s("b", "B", parent: "a"), s("c", "C", parent: "a")])
        XCTAssertNil(cycle.parent["a"])
        XCTAssertNil(cycle.parent["b"])
        XCTAssertEqual(cycle.parent["c"], "a", "one whose chain only reaches a cycle keeps its parent")
    }

    func testAnUntitledAncestorIsNamedInThePath() {
        let tree = ShelfTree([s("p", ""), s("c", "Child", parent: "p")])
        XCTAssertEqual(tree.pathLabel("c"), "Untitled")
    }

    // MARK: The read

    private func document(_ id: String, _ fields: [String: Any]) -> [String: Any] {
        [
            "document": [
                "name": "projects/noteletter-7a111/databases/(default)/documents/tags/\(id)",
                "fields": fields,
            ],
            "readTime": "2026-11-05T00:00:00Z",
        ]
    }

    func testAReaderWithNoShelvesIsAnEmptyListNotAFailure() {
        XCTAssertEqual(ShelfRead.shelves(from: [["readTime": "2026-11-05T00:00:00Z"]]), [])
    }

    func testAnythingThatIsNotAnAnswerIsAFailureNotAnEmptyList() {
        XCTAssertNil(ShelfRead.shelves(from: nil))
        XCTAssertNil(ShelfRead.shelves(from: ["error": ["code": 403]]))
        XCTAssertNil(ShelfRead.shelves(from: [["error": ["code": 403, "message": "denied"]]]))
    }

    func testDropsAShelfBeingDeletedAndReadsTheFields() {
        let shelves = ShelfRead.shelves(from: [
            document("a", [
                "title": ["stringValue": "Attention"],
                "color": ["stringValue": "teal-500"],
                "document_count": ["integerValue": "3"],
                "parent_tag_id": ["stringValue": "p"],
            ]),
            document("gone", [
                "title": ["stringValue": "Gone"],
                "status": ["stringValue": "deleting"],
            ]),
            document("n", [
                "title": ["stringValue": "No count"],
                "parent_tag_id": ["nullValue": NSNull()],
            ]),
        ])
        XCTAssertEqual(shelves, [
            Shelf(id: "a", title: "Attention", color: "teal-500", documentCount: 3, parentId: "p"),
            Shelf(id: "n", title: "No count", color: nil, documentCount: nil, parentId: nil),
        ])
    }

    func testTheQueryIsTheReadersOwnInTheSubscriptionsOrderWithNoEmbedding() throws {
        let body = ShelfRead.query(uid: "u1")
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""fieldPath":"user_id""#))
        XCTAssertTrue(json.contains(#""stringValue":"u1""#))
        XCTAssertTrue(json.contains(#""direction":"DESCENDING""#))
        XCTAssertFalse(json.contains("embedding"))
        XCTAssertTrue(json.contains(#""collectionId":"tags""#))
        XCTAssertFalse(json.contains("limit"), "a list that stopped short would read as shelves the reader does not have")
    }

    func testNoKeyAtAllWithNoneChosen() {
        let body: [String: Any] = ["url": "https://example.com", "type": "article"]
        XCTAssertNil(ShelfRead.adding([], to: body)["tagIds"])
        XCTAssertEqual(ShelfRead.adding([], to: body).count, 2)
        XCTAssertEqual(ShelfRead.adding(["a", "b"], to: body)["tagIds"] as? [String], ["a", "b"])
    }
}
