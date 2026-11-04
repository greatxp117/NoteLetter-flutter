/// A link to a Notion page that is in the library opens it there (5.58.0,
/// ADR-212; `screens/reader.md` §A link to a Notion page in the library; web
/// `shared/notionLinks.js` and `api.js` `resolveNotionPages`).
///
/// ADR-210 draws a Notion page's sub-page, its "link to page" block and its
/// page mentions as the page's address in Notion. Sharing a page with
/// NoteLetter shares every page under it, so those pages are usually in the
/// library too — and the link left the app for a copy the reader already
/// holds. The Reader looks the pages up when the manuscript is drawn
/// (`FirestoreService.resolveNotionPages`) and redraws each one it finds as a
/// link into the Reader.
///
/// Pure: no Firebase import. The lookup's RULE is here and asserted; the two
/// Firestore reads it makes are handed in (`fake_cloud_firestore` cannot
/// resolve against this SDK — CLAUDE.md).
library;

import 'package:html/parser.dart' as html_parser;

import '../models/document.dart' show Document, tsMs;

const Set<String> _notionHosts = {'www.notion.so', 'notion.so'};
final RegExp _pageIdAtEnd = RegExp(r'(?:^|-)([0-9a-fA-F]{32})$');

/// The page a Notion link names, as 32 lowercase hex digits, or null.
///
/// Host `www.notion.so` or `notion.so`, **no fragment**, and a last path
/// segment ending in the page's 32 hex digits (`/{id}`, `/{Title}-{id}`). A
/// link with a fragment points at a BLOCK inside a page (ADR-210's link to a
/// Notion-hosted file) and is not a page link.
String? notionPageId(String? href) {
  if (href == null || href.isEmpty) return null;
  final Uri u;
  try {
    u = Uri.parse(href);
  } on FormatException {
    return null;
  }
  final scheme = u.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  if (!_notionHosts.contains(u.host.toLowerCase())) return null;
  // A non-empty fragment, as web's `URL.hash` (empty for a bare trailing `#`).
  if (u.fragment.isNotEmpty) return null;
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final m = _pageIdAtEnd.firstMatch(segs.last);
  return m?.group(1)!.toLowerCase();
}

/// As the API answers it, and as `cloud_import_jobs.provider_file_id` stores
/// it: 8-4-4-4-12.
String dashedNotionId(String id) => '${id.substring(0, 8)}-'
    '${id.substring(8, 12)}-${id.substring(12, 16)}-'
    '${id.substring(16, 20)}-${id.substring(20)}';

final RegExp _hrefRe = RegExp(r'href="([^"]*)"');

/// The distinct Notion pages a set of passages links to, in first-seen order.
List<String> notionPageIdsIn(Iterable<String?> htmls) {
  final ids = <String>{};
  for (final h in htmls) {
    for (final m in _hrefRe.allMatches(h ?? '')) {
      final id = notionPageId(m.group(1)!.replaceAll('&amp;', '&'));
      if (id != null) ids.add(id);
    }
  }
  return ids.toList();
}

/// The attribute a redrawn link carries: the document it opens.
const String notionDocAttribute = 'data-nl-doc';

/// Redraws each Notion page link in [html] whose page [links] resolved (page
/// id → document id) as a link into the Reader: the reader address, no new
/// tab, and [notionDocAttribute] for the tap. Applied to the HTML being DRAWN,
/// after sanitising — never to what an edit saves. Returns [html] untouched
/// when nothing resolved or nothing in it is a resolved link.
String rewriteNotionLinks(String html, Map<String, String> links) {
  if (links.isEmpty || !html.contains('notion.so')) return html;
  final frag = html_parser.parseFragment(html);
  var changed = false;
  for (final a in frag.querySelectorAll('a')) {
    final href = a.attributes['href'];
    if (href == null) continue;
    final id = notionPageId(href);
    final docId = id == null ? null : links[id];
    if (docId == null) continue;
    a.attributes['href'] = '/reader/$docId';
    a.attributes.remove('target');
    a.attributes.remove('rel');
    a.attributes[notionDocAttribute] = docId;
    changed = true;
  }
  return changed ? frag.outerHtml : html;
}

/// The most page ids one `in` filter takes (INV-02, the Firestore limit).
const int notionIdsPerQuery = 30;

/// Which document each Notion page is, by `_refresh_target`'s rules.
///
/// A document does not record its Notion page id; its import job does.
/// [queryJobs] reads the reader's `cloud_import_jobs` filtered `user_id ==
/// uid` and `provider_file_id in` the dashed ids — at most
/// [notionIdsPerQuery] to a query. Per page, its rows newest first by
/// `created_at`; the first with a `document_id`, a `skip_reason` other than
/// `duplicate`, and a document that exists and is the reader's names the
/// page's document.
///
/// [held] is the documents subscription's ids: a candidate it holds needs no
/// read. One it does not is read once through [readDocument]; a deleted
/// document's read is refused by the rules, which is the same answer — not in
/// the library — so a refused or failed read is "not the page".
///
/// Throws when a jobs query fails; the caller leaves every link as written.
Future<Map<String, String>> resolveNotionPagesWith(
  Iterable<String> pageIds, {
  required String uid,
  required Future<List<Map<String, dynamic>>> Function(
          String uid, List<String> providerFileIds)
      queryJobs,
  required Future<Document?> Function(String docId) readDocument,
  Set<String>? held,
}) async {
  final out = <String, String>{};
  final ids = {
    for (final id in pageIds)
      if (id.isNotEmpty) id,
  }.toList();
  if (ids.isEmpty) return out;

  final byPage = <String, List<Map<String, dynamic>>>{};
  for (var i = 0; i < ids.length; i += notionIdsPerQuery) {
    final end = (i + notionIdsPerQuery).clamp(0, ids.length);
    final rows = await queryJobs(
        uid, [for (final id in ids.sublist(i, end)) dashedNotionId(id)]);
    for (final r in rows) {
      final docId = r['document_id'];
      if (docId is! String || docId.isEmpty) continue;
      if (r['skip_reason'] == 'duplicate') continue;
      final k = '${r['provider_file_id'] ?? ''}'
          .replaceAll('-', '')
          .toLowerCase();
      (byPage[k] ??= []).add(r);
    }
  }

  final isMine = <String, bool>{};
  for (final MapEntry(key: k, value: rows) in byPage.entries) {
    rows.sort((a, b) =>
        (tsMs(b['created_at']) ?? 0).compareTo(tsMs(a['created_at']) ?? 0));
    for (final r in rows) {
      final id = r['document_id'] as String;
      if (!isMine.containsKey(id)) {
        if (held != null && held.contains(id)) {
          isMine[id] = true;
        } else {
          try {
            final d = await readDocument(id);
            isMine[id] = d != null && d.userId == uid;
          } catch (_) {
            // Deliberately no failure (ADR-212 §2): the rules refuse a read of
            // a deleted document, so a refused read IS the answer "not in the
            // library", and the link stays Notion's, which still works.
            isMine[id] = false;
          }
        }
      }
      if (isMine[id]!) {
        out[k] = id;
        break;
      }
    }
  }
  return out;
}
