import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/tag.dart';
import '../state/tags_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

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
                    style: GoogleFonts.sourceSerif4(
                        fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Organize your library with tags.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                const SizedBox(height: 20),
                if (notifier.loading)
                  const Center(child: CircularProgressIndicator())
                else if (notifier.tags.isEmpty)
                  Text('No tags yet. Create one to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted))
                else
                  ...notifier.tags.map((t) => _TagRow(
                        tag: t,
                        muted: muted,
                        onEdit: () => _edit(existing: t),
                        onDelete: () => _delete(t),
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

  const _TagRow({
    required this.tag,
    required this.muted,
    required this.onEdit,
    required this.onDelete,
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _parseColor(tag.color) ?? muted,
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

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
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
  late final TextEditingController _color =
      TextEditingController(text: widget.existing?.color ?? '');

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _color.dispose();
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
          TextField(
            controller: _color,
            decoration:
                const InputDecoration(labelText: 'Color (hex, e.g. #9D352D)'),
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
                _color.text.trim().isEmpty ? null : _color.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
