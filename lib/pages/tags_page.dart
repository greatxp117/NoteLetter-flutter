import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tag.dart';
import '../state/tags_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/kit/kit.dart';
import '../widgets/app_toast.dart';
import 'tags/split_shelf_sheet.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';

/// Tags — list/create/edit/delete over the live tags subscription. Mutations go
/// through `fn_*` (INV-04). See spec/api/tags.md.
class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<TagsNotifier>().start());
  }

  Future<void> _edit({Tag? existing}) async {
    final result = await showDialog<_TagDraft>(
      context: context,
      builder: (_) => _TagDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final notifier = context.read<TagsNotifier>();
    final err = existing == null
        ? await notifier.createTag(result.title,
            description: result.description, color: result.color)
        : await notifier.updateTag(existing.id,
            title: result.title,
            description: result.description,
            color: result.color);
    if (!mounted) return;
    if (err != null) AppToast.show(context, err, type: ToastType.error);
  }

  /// Review-before-write: the sheet returns true only after fn_split_shelf
  /// succeeded. The parent shelf is kept either way (ADR-025) — a parent
  /// deleted the moment it empties would be silently re-created by the
  /// auto-tagger the next time a document fits none of the children.
  Future<void> _split(Tag tag) async {
    await SplitShelfSheet.show(context, tag.id, tag.title);
    // No reload: tags are a live subscription (INV-02), so the new shelves and
    // the parent's recomputed count arrive on their own.
  }

  Future<void> _delete(Tag tag) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text('“${tag.title}” will be removed from all documents.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.critical),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<TagsNotifier>().deleteTag(tag.id);
    if (!mounted) return;
    if (err != null) AppToast.show(context, err, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer<TagsNotifier>(
      builder: (context, notifier, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: primary,
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('New tag'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tags',
                    style: AppTheme.serif(
                        fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Organize your library with tags.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                const SizedBox(height: 20),
                if (notifier.loading)
                  const Center(child: CircularProgressIndicator())
                // INV-24 (ADR-071): "No tags yet. Create one to get started."
                // is an instruction to duplicate tags the reader already has.
                else if (notifier.error != null)
                  KitFailureBlock(
                    sentence: 'Your tags could not be read.',
                    detail: notifier.error!,
                  )
                else if (notifier.tags.isEmpty)
                  Text('No tags yet. Create one to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted))
                else
                  ...notifier.tags.map((t) => _TagRow(
                        tag: t,
                        muted: muted,
                        onEdit: () => _edit(existing: t),
                        onDelete: () => _delete(t),
                        onSplit: () => _split(t),
                      )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TagRow extends StatelessWidget {
  final Tag tag;
  final Color muted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSplit;

  const _TagRow({
    required this.tag,
    required this.muted,
    required this.onEdit,
    required this.onDelete,
    required this.onSplit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: AppRadius.mdR,
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.shelfColor(tag.color) ?? muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tag.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (tag.source == 'auto_created') ...[
                      const SizedBox(width: 6),
                      Text('auto',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: muted)),
                    ],
                  ],
                ),
                if ((tag.description ?? '').isNotEmpty)
                  Text(tag.description!,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ),
          // 2.20.0 — offered only at >= 5 volumes. ABSENT below that rather
          // than disabled: the endpoint 400s there, and a control that cannot
          // work is worse than no control.
          if (tag.documentCount >= splitMinDocuments)
            IconButton(
                tooltip: 'Split this shelf',
                icon: const Icon(Icons.call_split, size: 18),
                onPressed: onSplit),
          IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit),
          IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: AppColors.critical),
              onPressed: onDelete),
        ],
      ),
    );
  }

}

class _TagDraft {
  final String title;
  final String? description;
  final String? color;
  const _TagDraft(this.title, this.description, this.color);
}

class _TagDialog extends StatefulWidget {
  final Tag? existing;
  const _TagDialog({this.existing});

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _desc =
      TextEditingController(text: widget.existing?.description ?? '');
  // 2.15.0 (ADR-022): a shelf's colour is a design-token NAME from a closed
  // set of ten, not a colour value. Held as a nullable name rather than free
  // text — the old field was labelled "Color (hex, e.g. #9D352D)", which could
  // not produce a conforming value and invited a 400 for anything the user
  // typed that was not a valid 6-digit hex.
  late String? _color = widget.existing?.color;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New tag' : 'Edit tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            autofocus: true,
          ),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Colour',
                style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(height: 8),
          // The ten names are the whole writable vocabulary. A legacy hex on an
          // existing shelf still RENDERS (AppColors.shelfColor tolerates it and
          // there is no backfill) — it simply matches no swatch, so saving
          // without touching this leaves the stored value alone.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in AppColors.shelfColors.entries)
                _Swatch(
                  name: entry.key,
                  color: entry.value,
                  selected: _color == entry.key,
                  onTap: () => setState(
                      () => _color = _color == entry.key ? null : entry.key),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              _TagDraft(
                title,
                _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                _color,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One shelf colour. Labelled by its token name for screen readers, because a
/// bare circle names nothing.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: name,
      selected: selected,
      button: true,
      child: Tooltip(
        message: name,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
