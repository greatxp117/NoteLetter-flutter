import '../../models/document.dart';
import '../../models/tag.dart';
import '../../theme/app_colors.dart';
import '../../widgets/kit/kit.dart';

/// A document as a volume on a kit shelf ([KitBook]) — the one mapping both
/// screens that draw the shelf use (Sources' shelf and card views, the
/// Library's ledges). Its shelf is the FIRST of [shelves], in shelf order,
/// that the document is on — the reference's `shelves.find(...)`, so the band
/// and the label agree with the row's subtitle.
KitBook bookOf(Document d, List<Tag> shelves) {
  Tag? shelf;
  for (final s in shelves) {
    if (d.tagIds.contains(s.id)) {
      shelf = s;
      break;
    }
  }
  return KitBook(
    id: d.id,
    title: d.title,
    kind: kitDocKind(d.type),
    passages: d.chunkCount ?? 0,
    words: d.wordCount,
    createdAt: d.createdAt,
    viewCount: d.viewCount,
    shelf: shelf?.title,
    shelfColor: AppColors.shelfColor(shelf?.color),
    sourceUrl: d.sourceUrl,
  );
}
