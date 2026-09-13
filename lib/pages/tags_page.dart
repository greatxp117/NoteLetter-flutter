import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/tag.dart';
import '../state/documents_notifier.dart';
import '../state/tags_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/kit/kit.dart';
import 'tags/shelf_parts.dart';

/// **Shelves — the index** (`screens/library.md` §Shelf color, §Shelf
/// granularity and splitting; composition per `screens/sources.md`
/// §Composition, which is what every index screen takes).
///
/// A shelf **is** a `/tags` document: its title, description and colour are tag
/// fields, written through `fn_create_tag`/`fn_update_tag` (INV-04), and the
/// volumes on it are a client-side grouping over the documents subscription
/// (INV-02) — there is no shelves collection.
///
/// Composition, every part from the kit:
///
/// * **Frame** Index (980) inside a scroll container — §1.4/§1.5.
/// * **Header** chapter opening: folio `Library · {n} shelves`, the title, and
///   a standfirst naming how many volumes are shelved.
/// * **Body** a grid of §5.1 shelf cards, closed by the dashed *New shelf*
///   card that makes one.
///
/// Until F-08 this screen was a Material list of `_TagRow`s with an
/// `AlertDialog` editor and a `FloatingActionButton` — feature-complete, and a
/// different design (ADR-041).
///
/// The file keeps its name because `harness/failure_pattern_check.py` and
/// `spec/clients/flutter.md` §5 both address this surface as
/// `lib/pages/tags_page.dart`; it is the ROUTE that was renamed.
class ShelvesPage extends StatefulWidget {
  const ShelvesPage({super.key});

  @override
  State<ShelvesPage> createState() => _ShelvesPageState();
}

class _ShelvesPageState extends State<ShelvesPage> {
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
      context.read<DocumentsNotifier>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<TagsNotifier, DocumentsNotifier>(
      builder: (context, tags, docs, _) {
        if (tags.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final shelves = tags.tags;
        final complete = docs.complete;
        // INV-24 (ADR-071): every figure on this screen is counted from two
        // subscriptions, so a failed one makes the folio and the standfirst
        // statements about a library we could not read.
        final error = tags.error ?? docs.error;

        return KitPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChapterOpening(
                folio: 'Library · ${plural(shelves.length, 'shelf', 'shelves')}',
                title: 'Shelves',
                standfirst:
                    'Group your volumes by subject, project, or year — each '
                    'shelf can feed your letter on its own. '
                    '${complete.length} volumes, shelved.',
              ),
              if (error != null) ...[
                KitFailureInline(
                    'Your shelves could not be read — $error'),
                const SizedBox(height: 20),
              ],
              KitCardGrid(
                columns: 3,
                // `.shelf-grid` gap 20 — the shelves grid's own metric; the
                // connect grid on Sources is 12, so the gap belongs to the
                // call site rather than to the widget.
                gap: AppSpacing.s5,
                // One column on a phone, as the reference does at 720px: two
                // 190pt cards cannot hold a serif shelf name and three volume
                // titles, and the lines that would be clipped are the ones
                // that say what is ON the shelf.
                compactColumns: 1,
                children: [
                  for (final s in shelves)
                    _shelfCard(context, s, complete),
                  if (_adding)
                    _NewShelfForm(
                      onCancel: () => setState(() => _adding = false),
                      onCreated: () => setState(() => _adding = false),
                    )
                  else
                    KitNewCard(
                      title: 'New shelf',
                      subtitle: 'Group volumes by subject or project',
                      onTap: () => setState(() => _adding = true),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shelfCard(BuildContext context, Tag shelf, List<Document> complete) {
    final vols = shelfVolumes(shelf, complete);
    final passages = shelfPassages(vols);
    return KitShelfCard(
      title: shelf.title,
      colorToken: shelf.color,
      volumes: vols.length,
      meta: '${plural(vols.length, 'volume', 'volumes')} · '
          '${plural(passages, 'passage', 'passages')}',
      volumeTitles: [
        for (final v in vols.take(3)) v.title.isEmpty ? 'Untitled' : v.title,
      ],
      moreCount: vols.length > 3 ? vols.length - 3 : 0,
      // Provenance is a LABEL (ADR-025): it never rolls counts up to a parent
      // and never nests one shelf under another in this index.
      badge: switch (shelf.source) {
        'auto_created' => 'auto',
        'split_from' => 'split',
        _ => null,
      },
      onTap: () => context.go('/shelves/${shelf.id}'),
    );
  }
}

/// Creating a shelf, in the card's own slot — the reference replaces the dashed
/// card with the form rather than opening a dialog, so the new shelf appears
/// where the reader was already looking.
class _NewShelfForm extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onCreated;

  const _NewShelfForm({required this.onCancel, required this.onCreated});

  @override
  State<_NewShelfForm> createState() => _NewShelfFormState();
}

class _NewShelfFormState extends State<_NewShelfForm> {
  final _name = TextEditingController();
  String _color = AppColors.shelfColors.keys.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Write before move: the card closes only after `fn_create_tag` answers, and
  /// a rejection stays on the form with the server's own sentence (§14.2). The
  /// reference had the rejection falling out of the `try` with only `busy`
  /// reset, so a failed create left the form sitting there looking idle.
  Future<void> _submit() async {
    final title = _name.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context
        .read<TagsNotifier>()
        .createTag(title, color: _color);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    return KitCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          KitTextField(
            controller: _name,
            placeholder: 'Shelf name…',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          ShelfSwatches(
            selected: _color,
            enabled: !_busy,
            onPick: (name) => setState(() => _color = name),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            KitFailureInline(_error!),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              KitButton.primary(
                _busy ? 'Creating…' : 'Create',
                onPressed:
                    _name.text.trim().isEmpty || _busy ? null : _submit,
              ),
              const SizedBox(width: 8),
              KitButton.ghost('Cancel',
                  onPressed: _busy ? null : widget.onCancel),
            ],
          ),
        ],
      ),
    );
  }
}
