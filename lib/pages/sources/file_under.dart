import 'package:flutter/material.dart';

import '../../models/tag.dart';
import '../../shared/shelf_tree.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// *File under* (5.46.0, ADR-201; `screens/sources.md` §The OAuth return and
/// §Cloud import; web `pages/sources/FileUnder.jsx`): the shelf every document
/// an import creates is filed under, instead of the shelf indexing would
/// choose. One control for the two places an import starts — the OAuth
/// return's Manifest and the Library's import picker — so the two cannot offer
/// different shelves or spell them differently.
///
/// The default is NO shelf: an import nobody filed is shelved as every other
/// document is (INV-12), and a default shelf would file a whole folder
/// somewhere the reader never chose. A nested shelf is spelled by its path
/// (*Theology › Patristics*), as Move into spells it.
const kAutoShelfLabel = 'NoteLetter chooses';

String _spell(ShelfTreeRow r) => [...r.path, r.shelf]
    .map((s) => s.title.isEmpty ? 'Untitled' : s.title)
    .join(shelfPathSep);

/// [id]'s path among [shelves], or null — no shelf chosen, or one that is no
/// longer in the library. A caller sends a shelf only while this names it, so
/// the select never shows *NoteLetter chooses* over a request that files.
String? shelfPathLabel(List<Tag> shelves, String? id) {
  if (id == null) return null;
  for (final r in ShelfTree(shelves).ordered()) {
    if (r.shelf.id == id) return _spell(r);
  }
  return null;
}

/// The control: the label *File under*, a select whose first option is
/// [kAutoShelfLabel] and then every shelf in tree order by its path, and the
/// [note] under it. On the Manifest it opens on a rule, 16 under it (`.or-field`);
/// the picker sets it 10 under ([top]).
class FileUnder extends StatelessWidget {
  final List<Tag> shelves;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool disabled;
  final String? note;
  final double top;

  const FileUnder({
    super.key,
    required this.shelves,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.note,
    this.top = 16,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final rows = ShelfTree(shelves).ordered();
    final names = {for (final r in rows) r.shelf.id: _spell(r)};
    // '' is *NoteLetter chooses*, as web's empty option value.
    final current = value != null && names.containsKey(value) ? value! : '';
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('File under',
              style: KitText.small(context, weight: FontWeight.w600)),
          const SizedBox(height: 7),
          Semantics(
            label: 'File under',
            child: KitSelect<String>(
              value: current,
              options: ['', ...names.keys],
              label: (id) => id.isEmpty ? kAutoShelfLabel : names[id]!,
              face: KitFieldFace.ui,
              onChanged:
                  disabled ? null : (id) => onChanged(id.isEmpty ? null : id),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 7),
            Text(note!,
                style: KitText.small(context, color: t.fgSubtle, height: 17)),
          ],
        ],
      ),
    );
  }
}
