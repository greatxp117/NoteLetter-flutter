import '../../widgets/kit/kit.dart' show kitDocKind;

/// One row of the Library's Kind facet (screens/sources.md §Composition,
/// *Sheet*; web `SRC_KINDS`). [types] names every `type` the facet holds;
/// `all` and `unread` hold none — they are not kinds.
class SourceFacet {
  final String id;
  final String label;
  final List<String>? types;

  const SourceFacet(this.id, this.label, {this.types});
}

/// The Library's Kind facet. The kinds **follow the covers** (kit §33), a step
/// finer than §6.4.1: Documents are PDFs, Word files and slides; Images are
/// images and image sets; Audio is podcasts and recordings; Video takes
/// uploaded video and `social_video`. Every writable `type` is held by exactly
/// one facet — `test/kit/d_library_kit_test.dart` asserts both directions, and
/// `doc_kind_check.py` reads this declaration (MISSING-TYPE, DOUBLE-TYPE,
/// UNKNOWN-TYPE), so keep its shape: one `SourceFacet(...)` per entry.
const kSourceFacets = <SourceFacet>[
  SourceFacet('all', 'All'),
  SourceFacet('epub', 'Books', types: ['epub']),
  SourceFacet('pdf', 'Documents', types: ['pdf', 'docx', 'pptx']),
  SourceFacet('web', 'Web clips', types: ['article', 'url']),
  SourceFacet('note', 'Notes', types: ['plain']),
  SourceFacet('image', 'Images', types: ['image', 'image_set']),
  SourceFacet('youtube', 'YouTube', types: ['youtube']),
  SourceFacet('podcast', 'Audio', types: ['podcast', 'audio']),
  SourceFacet('video', 'Video', types: ['video', 'social_video']),
  SourceFacet('instagram', 'Instagram', types: ['instagram']),
  SourceFacet('tiktok', 'TikTok', types: ['tiktok']),
  SourceFacet('unread', 'Unread'),
];

final Map<String, String> _facetOfType = {
  for (final f in kSourceFacets)
    for (final t in f.types ?? const <String>[]) t: f.id,
};

/// The facet a document's `type` files under (web `facetOf`). A `type` no
/// release has heard of falls through its §6.4.1 kind, and to *Notes* when
/// that kind is not a facet — so it still lands under a row the sheet draws.
String sourceFacetOf(String type) {
  final held = _facetOfType[type];
  if (held != null) return held;
  final kind = kitDocKind(type);
  return kSourceFacets.any((f) => f.id == kind && f.types != null)
      ? kind
      : 'note';
}

/// What the library takes (web `ADDABLE`): the empty library's sheet and Add a
/// source's. *Each up to · 100 MB* is true of every file but a video, which the
/// server takes up to 2 GB (4.13.0, ADR-049), so a second row says that.
const kAddable = <(String, String)>[
  ('Files', 'PDF, EPUB, Word, slides, Markdown, images, audio, video'),
  ('Each up to', '100 MB'),
  ('A video up to', '2 GB'),
  ('Links', 'Articles, videos, podcasts'),
];
