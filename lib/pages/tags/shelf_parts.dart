/// The pieces the shelves index and a single shelf both need.
///
/// Shared rather than retyped: the swatch set is a **closed vocabulary**
/// (`screens/library.md` §Shelf color), and a second copy of it on the detail
/// screen is how one surface comes to offer nine colours. The same goes for
/// what counts as a volume — a shelf that reports one size on the index and
/// another on its own page is the roll-up defect ADR-025 refused, arrived at by
/// accident.
library;

import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../theme/app_colors.dart';
import '../../widgets/kit/kit.dart';

/// The ten shelf colours, in the contract's order, each announced by its NAME.
///
/// The set is closed for writing and tolerant on reading: a legacy hex on an
/// existing shelf still renders (`AppColors.shelfColor`), it simply matches no
/// swatch here, so saving without touching this leaves the stored value alone.
class ShelfSwatches extends StatelessWidget {
  final String? selected;

  /// False while a write is in flight — the swatches are write-before-move, so
  /// the row cannot be re-picked before the request it is waiting on answers.
  final bool enabled;
  final ValueChanged<String> onPick;

  const ShelfSwatches({
    super.key,
    required this.selected,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in AppColors.shelfColors.entries)
          KitSwatch(
            color: entry.value,
            label: AppColors.shelfColorLabels[entry.key] ?? entry.key,
            selected: selected == entry.key,
            onTap: enabled ? () => onPick(entry.key) : null,
          ),
      ],
    );
  }
}

/// The volumes on a shelf — **complete** documents only, which is what every
/// "{n} volumes" figure in this app means.
List<Document> shelfVolumes(Tag shelf, List<Document> complete) =>
    complete.where((d) => d.tagIds.contains(shelf.id)).toList();

int shelfPassages(List<Document> vols) =>
    vols.fold<int>(0, (n, d) => n + (d.chunkCount ?? 0));

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Mar 4` — the reference's `toLocaleDateString('en-US', {month:'short',
/// day:'numeric'})`, which is what a shelf's dates are shown in.
String shortDate(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_months[d.month - 1]} ${d.day}';
}
