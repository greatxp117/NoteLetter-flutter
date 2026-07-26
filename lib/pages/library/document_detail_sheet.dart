import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/document.dart';
import '../../models/tag.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';

/// Library document-detail affordances (library.md): edit `sourcePriority` and
/// `tagIds` via `fn_update_document`. Priority is propagated to the document's
/// chunks server-side (search/newsletter scoring); tagIds replaces the list.
class DocumentDetailSheet extends StatefulWidget {
  final String docId;
  const DocumentDetailSheet({super.key, required this.docId});

  /// Returns true if a save was made (so the caller can toast).
  static Future<bool?> show(BuildContext context, String docId) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DocumentDetailSheet(docId: docId),
    );
  }

  @override
  State<DocumentDetailSheet> createState() => _DocumentDetailSheetState();
}

class _DocumentDetailSheetState extends State<DocumentDetailSheet> {
  Document? _doc;
  List<Tag> _tags = const [];
  late Set<String> _selectedTags;
  double _priority = 0.5;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fs = FirestoreService.instance;
    final results = await Future.wait([fs.getDocument(widget.docId), fs.getTags()]);
    if (!mounted) return;
    final doc = results[0] as Document?;
    setState(() {
      _doc = doc;
      _tags = results[1] as List<Tag>;
      _priority = doc?.sourcePriority ?? 0.5;
      _selectedTags = {...?doc?.tagIds};
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.instance.updateDocument(widget.docId, {
        'sourcePriority': double.parse(_priority.toStringAsFixed(2)),
        'tagIds': _selectedTags.toList(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save changes.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _priorityLabel(double p) {
    if (p >= 0.8) return 'High — favored in search & letters';
    if (p <= 0.3) return 'Low — rarely surfaced';
    return 'Normal';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.foregroundDark : AppColors.foregroundLight;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final card = isDark ? AppColors.cardDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface =
        isDark ? AppColors.secondaryDark : AppColors.secondaryLight;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final accentFg =
        isDark ? AppColors.primaryForegroundDark : AppColors.primaryForeground;

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(_doc?.title ?? 'Document',
                    style: GoogleFonts.sourceSerif4(
                        fontSize: 18, fontWeight: FontWeight.w700, color: fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 20),
                Text('SOURCE PRIORITY',
                    style: TextStyle(fontFamily: 'Geist', 
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: muted)),
                Row(children: [
                  Expanded(
                    child: Slider(
                      value: _priority,
                      activeColor: primary,
                      inactiveColor: border,
                      onChanged: (v) => setState(() => _priority = v),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(_priority.toStringAsFixed(2),
                        textAlign: TextAlign.end,
                        style:
                            GoogleFonts.robotoMono(fontSize: 13, color: fg)),
                  ),
                ]),
                Text(_priorityLabel(_priority),
                    style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: muted)),
                const SizedBox(height: 24),
                Text('TAGS',
                    style: TextStyle(fontFamily: 'Geist', 
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: muted)),
                const SizedBox(height: 10),
                if (_tags.isEmpty)
                  Text('No tags yet — create some on the Tags screen.',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: muted))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags.map((t) {
                      final on = _selectedTags.contains(t.id);
                      return GestureDetector(
                        onTap: () => setState(() {
                          on
                              ? _selectedTags.remove(t.id)
                              : _selectedTags.add(t.id);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: on ? primary : surface,
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: on ? primary : border),
                          ),
                          child: Text(t.title,
                              style: TextStyle(fontFamily: 'Geist', 
                                  fontSize: 13,
                                  color: on ? accentFg : fg)),
                        ),
                      );
                    }).toList(),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(fontFamily: 'Geist', 
                          fontSize: 13, color: AppColors.critical)),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ]),
              ],
            ),
    );
  }
}
