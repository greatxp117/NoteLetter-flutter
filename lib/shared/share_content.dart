// What a share hands NoteLetter, decided before anything is read (F-123).
//
// The Android half of the share sheet (iOS's is the native `ios/Share`
// extension, F-122). This is `ShareViewController.extractContent` ported to a
// pure function over what `MainActivity` DESCRIBES — a name, a size and a type
// per stream, or why those could not be read — so it can be asserted case for
// case without a device, and so a refusal is said before a byte is copied.
//
// The order is iOS's: a web link first, then photos, then one file. Selected
// text with no link in it is not accepted — only the browser extension sends
// passages.
import '../state/upload_notifier.dart' show detectUrlType, normalizeUrl;
import 'playlist.dart' show playlistLabel, playlistType;
import 'upload_types.dart';

/// One stream of a share, as `MainActivity.item` describes it.
class SharedStream {
  final String uri;
  final String name;
  final int size;
  final String mimeType;

  /// Why its name, size or type could not be read — the system's words.
  final String? error;

  const SharedStream({
    required this.uri,
    required this.name,
    this.size = 0,
    this.mimeType = '',
    this.error,
  });

  factory SharedStream.fromMap(Map<Object?, Object?> m) => SharedStream(
    uri: (m['uri'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    size: (m['size'] as num?)?.toInt() ?? 0,
    mimeType: (m['mime'] as String?) ?? '',
    error: m['error'] as String?,
  );
}

/// The whole share: its text (`EXTRA_TEXT`) and its streams (`EXTRA_STREAM`).
class SharePayload {
  final String? text;
  final List<SharedStream> items;

  const SharePayload({this.text, this.items = const []});

  factory SharePayload.fromMap(Map<Object?, Object?> m) => SharePayload(
    text: m['text'] as String?,
    items: [
      for (final i in (m['items'] as List?) ?? const [])
        if (i is Map) SharedStream.fromMap(i),
    ],
  );
}

/// iOS's `SharedContent`, case for case.
sealed class SharedContent {
  const SharedContent();
}

class SharedLink extends SharedContent {
  /// Normalized — the string `fn_ingest_url` is sent, verbatim (ADR-120).
  final String url;

  /// Detected, never asked (INV-07).
  final String type;
  const SharedLink(this.url, this.type);
}

class SharedImages extends SharedContent {
  final List<SharedStream> items;

  /// Why some of the photos could not be read, when others could. iOS drops
  /// them without a word; a photo that silently is not in the set is a
  /// failure nobody can see, so it is said on the card.
  final String? unreadable;
  const SharedImages(this.items, {this.unreadable});

  /// One image set is at most 20 (`api/uploads.md`). iOS's activation rule
  /// never offers more; an Android share filter cannot count, so the card
  /// says so, in the iOS view model's words, and offers no upload.
  String? get countRefusal =>
      items.isEmpty || items.length > maxImageSet ? imageCountRefusal : null;
}

class SharedFile extends SharedContent {
  final SharedStream item;
  const SharedFile(this.item);
}

/// Something this screen HANDLES that could not be read — never told as an
/// unsupported type (iOS D6).
class SharedUnreadable extends SharedContent {
  final String reason;
  const SharedUnreadable(this.reason);
}

/// A file the server would refuse, refused here first in its own words.
class SharedRefused extends SharedContent {
  final String filename;
  final String reason;
  const SharedRefused(this.filename, this.reason);
}

class SharedNothing extends SharedContent {
  const SharedNothing();
}

const int maxImageSet = 20;
const String imageCountRefusal = 'Select between 1 and 20 images.';

/// iOS's `readFailure`: the system's own words, named as a read failure so
/// the sentence is never mistaken for one about the kind of thing shared.
String readFailure(String reason) => 'It couldn’t be read — $reason';

final RegExp _webLink = RegExp(
  r'''https?://[^\s<>"']+''',
  caseSensitive: false,
);

/// The web link a share's text carries, normalized, or null. Android has no
/// link type of its own: a browser shares the address as text, often after
/// the page's title, so the first http(s) address is the link. A bare
/// address alone is one too (ADR-120); a `file://` never is.
String? linkIn(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return null;
  final whole = normalizeUrl(t);
  if (whole != null) return whole;
  final m = _webLink.firstMatch(t);
  if (m == null) return null;
  final found = m[0]!.replaceFirst(RegExp(r'''[.,;:!?)\]}'"]+$'''), '');
  return normalizeUrl(found);
}

bool _isImage(SharedStream s) {
  final mime = s.mimeType.toLowerCase();
  if (mime.startsWith('image/')) return true;
  if (mime.isNotEmpty && mime != 'application/octet-stream') return false;
  final i = s.name.lastIndexOf('.');
  return i >= 0 && imageExts.contains(s.name.substring(i + 1).toLowerCase());
}

SharedContent classifyShare(SharePayload p) {
  // A link is a web address — and only when no file came with the text: a
  // share of a file carries its caption as text, and a file is a FILE (the
  // lesson of iOS's Files items drawn as links).
  if (p.items.isEmpty) {
    final url = linkIn(p.text);
    final type = url == null ? null : detectUrlType(url);
    return url == null || type == null
        ? const SharedNothing()
        : SharedLink(url, type);
  }

  // Why a stream we DO handle could not be read. Held until the end: another
  // stream may still work, and only an empty-handed scan reports it alone.
  String? unreadable;
  final readable = <SharedStream>[];
  for (final s in p.items) {
    final error = s.error;
    if (error != null) {
      unreadable ??= readFailure(error);
    } else {
      readable.add(s);
    }
  }

  final images = readable.where(_isImage).toList();
  if (images.isNotEmpty) {
    for (final im in images) {
      final refusal = uploadRejection(
        name: im.name,
        size: im.size,
        mimeType: im.mimeType,
      );
      if (refusal != null) return SharedRefused(im.name, refusal);
    }
    return SharedImages(images, unreadable: unreadable);
  }

  for (final s in readable) {
    // Refused before the read: an unsupported or oversized file is never
    // copied at all.
    final refusal = uploadRejection(
      name: s.name,
      size: s.size,
      mimeType: s.mimeType,
    );
    if (refusal != null) return SharedRefused(s.name, refusal);
    return SharedFile(s);
  }

  if (unreadable != null) return SharedUnreadable(unreadable);
  return const SharedNothing();
}

/// The kind a link files as — iOS `URLContentType.label`, the words its card
/// prints after "Files as: ".
String linkKindLabel(String type) {
  switch (type) {
    case playlistType:
      return playlistLabel;
    case 'youtube':
      return 'YouTube video';
    case 'instagram':
      return 'Instagram post';
    case 'tiktok':
      return 'TikTok video';
    case 'podcast':
      return 'Podcast episode';
    case 'social_video':
      return 'Video post';
    case 'article':
      return 'Article';
  }
  // INV-07's table is open: a type a later detector adds files as a page.
  return 'Article';
}

/// The address on the Link card: at most [max] characters, truncated in the
/// MIDDLE (`screens/share-sheet.md`), so the host and the end of the path —
/// the two parts that tell links apart — both stay on screen.
String middleEllipsis(String s, {int max = 90}) {
  if (s.length <= max) return s;
  final tail = (max - 1) ~/ 3;
  final head = max - 1 - tail;
  return '${s.substring(0, head)}…${s.substring(s.length - tail)}';
}
