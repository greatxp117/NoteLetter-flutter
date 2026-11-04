/// The documents subscription's window (5.58.0, ADR-211; web
/// `shared/documentWindow.js`): the newest [documentWindow] of the reader's
/// documents, `created_at desc`. Almost every screen counts from it — the
/// folios, the catalogue, the shelves, the map — so a count over it is the
/// library's only while the window is not full.
///
/// It was 200 from 1.x until 5.58.0, and the two folios printed it as the
/// library: Xavier's 551 volumes read "200 volumes" before a 61-page import
/// and after it. A row is ~3.3 KB (the embedding lives on chunks), so 2,000 is
/// ~6.6 MB at the bound.
///
/// ONE constant, read by `FirestoreService.subscribeDocuments` and by every
/// label that names the window, so the two cannot disagree. Pure, with no
/// Firebase import, so the map's layout and its tests can read it.
library;

const int documentWindow = 2000;

/// Full when the subscription returned the whole window — counted over EVERY
/// row, not only the complete ones: a full window of which some are still
/// processing is still full, and the complete count alone would miss it.
bool windowFull(List<Object?>? documents) =>
    (documents?.length ?? 0) >= documentWindow;
