/// Where the Reader was opened FROM (4.65.0, ADR-101).
///
/// The Reader is the one screen every other screen links INTO, and its back
/// control therefore names the screen it was opened from and returns there. It
/// said `Library` and went to `/sources` whatever opened it, which was wrong on
/// six of the seven paths in — and wrong out loud, since the one control that
/// names a destination named the wrong one.
///
/// The origin travels as `?from=` on the Reader's own address, so it survives a
/// reload and a shared link. On this client the Reader is also PUSHED from a
/// citation, so the platform back gesture arrives in the same place.
library;

import '../models/tag.dart';

/// The label for every route a screen can open the Reader from. **Closed**: a
/// route with no entry here gets [readerOriginDefault] rather than a name
/// guessed from its path. Both directions are gated
/// (`test/contract/reader_origin_test.dart`), because a one-way map is half a
/// vocabulary — the `docKind()`/`KIND_ORDER` shape that dropped every podcast
/// out of the Sources view.
const Map<String, String> readerOriginLabels = <String, String>{
  '/': 'Home',
  '/sources': 'Library',
  '/search': 'Search',
  '/ask': 'Ask',
  '/activity': 'Activity',
  '/letters': 'Letters',
  '/shelves': 'Shelves',
  '/study': 'Deep study',
};

/// What the Reader shows when it knows nothing about where the reader came
/// from: a cold open — a newsletter link, a notification, a shared URL — and
/// every `from` this file refuses. It is 1.0.0's behaviour, and the honest one.
const ReaderOrigin readerOriginDefault = ReaderOrigin('Library', '/sources');

class ReaderOrigin {
  final String label;
  final String path;

  const ReaderOrigin(this.label, this.path);
}

/// Resolve a `?from=` into a label and a destination.
///
/// A value is honoured only when it is one of the app's OWN addresses, matched
/// whole: a foreign origin (`https://…`, `//host`), a path this app does not
/// have, a query or fragment riding inside a segment, and anything with a
/// trailing slash are all dropped rather than guessed at.
///
/// [tags] names a shelf origin with the shelf's own title when the caller has
/// the shelves loaded; a shelf that is gone or still loading falls back to the
/// index's name, because the reader still came from there.
ReaderOrigin readerOrigin(String? from, {List<Tag> tags = const []}) {
  if (from == null || from.isEmpty) return readerOriginDefault;
  if (!from.startsWith('/') || from.startsWith('//')) return readerOriginDefault;
  if (from.contains('?') || from.contains('#')) return readerOriginDefault;
  if (from.length > 1 && from.endsWith('/')) return readerOriginDefault;

  final label = readerOriginLabels[from];
  if (label != null) return ReaderOrigin(label, from);

  // Ask carries two id-bearing forms, and both are the same screen to a reader:
  // the conversation they left (ADR-101) and the shelf-scoped screen they
  // started one from (ADR-098).
  final ask = RegExp(r'^/ask/(shelf|thread)/([A-Za-z0-9_.~:@+-]+)$');
  if (ask.hasMatch(from)) return ReaderOrigin(readerOriginLabels['/ask']!, from);

  // A shelf is named by the shelf, not by the index — it is the one origin the
  // reader thinks of by name.
  final shelf = RegExp(r'^/shelves/([A-Za-z0-9_.~:@+-]+)$').firstMatch(from);
  if (shelf != null) {
    final id = shelf.group(1);
    for (final tag in tags) {
      if (tag.id == id && tag.title.isNotEmpty) {
        return ReaderOrigin(tag.title, from);
      }
    }
    return ReaderOrigin(readerOriginLabels['/shelves']!, from);
  }

  return readerOriginDefault;
}
