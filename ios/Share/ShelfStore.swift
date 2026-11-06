import Combine
import FirebaseAuth
import Foundation

/// The share sheet's shelves: the reader's list and what they have chosen (kit
/// §20.3, 5.73.0, ADR-238). The extension has no Firestore SDK and no session of
/// its own to give one, so the list is one read over Firestore REST with the ID
/// token (`share-sheet.md` §Endpoints used), for a surface that lives for a few
/// seconds. The same query and the same rules as the app's subscription.
@MainActor
final class ShelfStore: ObservableObject {
    /// A failed read is NOT an empty list: the picker says so and offers no create
    /// row, and an add still goes through with what is chosen.
    enum Phase: Equatable {
        case loading
        case failed
        case loaded
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var shelves: [Shelf] = []
    @Published private(set) var chosen: [String] = []

    private var started = false

    /// The chips. An id that resolves to no shelf draws nothing (§20).
    var chosenShelves: [Shelf] {
        chosen.compactMap { id in shelves.first { $0.id == id } }
    }

    /// Reads once. Call it only for a signed-in reader with something to add.
    func start() {
        guard !started else { return }
        started = true
        Task { await read() }
    }

    func choose(_ id: String) {
        if !chosen.contains(id) { chosen.append(id) }
    }

    func takeOff(_ id: String) {
        chosen.removeAll { $0 == id }
    }

    /// A shelf just made in the form: the read that ran on opening cannot know it,
    /// so it joins the list here, chosen.
    func adopt(_ shelf: Shelf) {
        if !shelves.contains(where: { $0.id == shelf.id }) { shelves.insert(shelf, at: 0) }
        choose(shelf.id)
    }

    private func read() async {
        guard let answer = await Self.fetch(), let list = ShelfRead.shelves(from: answer) else {
            phase = .failed
            return
        }
        shelves = list
        phase = .loaded
    }

    /// The decoded `:runQuery` answer, or nil for anything that is not one.
    private static func fetch() async -> Any? {
        do {
            guard let uid = Auth.auth().currentUser?.uid,
                  let token = try await APIClient.tokenProvider(),
                  let url = URL(string: "\(EmulatorConfig.firestoreBase):runQuery") else { return nil }
            // No deadline of ours to outlast: Foundation's own would do, and this
            // is the same floor every unlisted `fn_*` gets.
            var request = URLRequest(url: url, timeoutInterval: EndpointBudgets.defaultTimeout)
            request.httpMethod = HTTPMethod.post.rawValue
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ShelfRead.query(uid: uid))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            print("NoteLetter (share): the tags read failed — \(error)")
            return nil
        }
    }
}
