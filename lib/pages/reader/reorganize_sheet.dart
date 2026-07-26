import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import 'reader_ui.dart';

/// Reader "Reorganize document" plan sheet (reader.md 1.2.0). Analyze → editable
/// plan (per-section destination + split/copy) → explicit confirm for any split
/// → execute → live progress off the `/reorg_plans/{planId}` subscription.
/// Execution never happens outside this flow (INV-13).
class ReorganizeSheet extends StatefulWidget {
  final String docId;
  final VoidCallback onExecuted;
  const ReorganizeSheet(
      {super.key, required this.docId, required this.onExecuted});

  static Future<void> show(
      BuildContext context, String docId, VoidCallback onExecuted) {
    return showDialog(
      context: context,
      builder: (_) => ReorganizeSheet(docId: docId, onExecuted: onExecuted),
    );
  }

  @override
  State<ReorganizeSheet> createState() => _ReorganizeSheetState();
}

class _Choice {
  String? destKey;
  String? mode;
  bool include;
  _Choice({this.destKey, this.include = true});
}

class _ReorganizeSheetState extends State<ReorganizeSheet> {
  Map<String, dynamic>? _plan;
  String? _error;
  final Map<String, _Choice> _choices = {};
  bool _confirming = false;
  Map<String, dynamic>? _live;
  String _defaultMode = 'split';
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.getOrganizationSettings().then((s) {
      if (mounted) setState(() => _defaultMode = s.defaultReorgMode);
    }).catchError((_) {});
    Api.instance.analyzeReorganization(widget.docId).then((p) {
      if (!mounted) return;
      setState(() {
        _plan = p;
        for (final s in (p['sections'] as List? ?? [])) {
          final dests = s['destinations'] as List? ?? [];
          _choices[s['section_id']] = _Choice(
            destKey: dests.isNotEmpty ? _destKey(dests[0]) : null,
            include: dests.isNotEmpty,
          );
        }
      });
    }).catchError((e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : 'Analysis failed.');
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _destKey(dynamic d) =>
      '${d['kind']}:${d['folder_id'] ?? d['document_id']}';
  String _destLabel(dynamic d) =>
      d['kind'] == 'folder' ? (d['path'] ?? 'folder') : (d['title'] ?? 'document');
  String _pct(dynamic x) => '${(((x ?? 0) as num) * 100).round()}%';

  List<Map<String, dynamic>> get _ops {
    final plan = _plan;
    if (plan == null) return [];
    final out = <Map<String, dynamic>>[];
    for (final s in (plan['sections'] as List? ?? [])) {
      final c = _choices[s['section_id']];
      if (c == null || !c.include || c.destKey == null) continue;
      final dest = (s['destinations'] as List).firstWhere(
          (d) => _destKey(d) == c.destKey,
          orElse: () => null);
      if (dest == null) continue;
      out.add({
        'section_id': s['section_id'],
        'destination': dest,
        'mode': c.mode ?? _defaultMode,
      });
    }
    return out;
  }

  bool get _hasSplit => _ops.any((o) => o['mode'] == 'split');

  Future<void> _execute() async {
    setState(() {
      _error = null;
      _confirming = false;
    });
    try {
      final res = await Api.instance
          .executeReorganization(_plan!['plan_id'], _ops);
      final planId = res['plan_id'] as String;
      setState(() => _live = {'status': res['status']});
      _sub = FirestoreService.instance.subscribeReorgPlan(planId).listen((p) {
        if (!mounted) return;
        setState(() => _live = p ?? _live);
        if (p?['status'] == 'done') widget.onExecuted();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Reorganize failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    return Dialog(
      backgroundColor: ui.dark ? ui.card : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ui.eyebrow('Reorganize this document'),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!,
                        style:
                            TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.critical)),
                  if (_plan == null && _error == null)
                    ui.note('Reading the document and drafting a plan…'),
                  if (_live != null)
                    _liveView(ui)
                  else if (_plan != null)
                    _planView(ui),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _liveView(ReaderUi ui) {
    final status = _live?['status'];
    final msg = status == 'executing'
        ? 'Reorganizing… sections are being routed to their destinations.'
        : status == 'done'
            ? 'Done. New documents are in your library; a snapshot of the original was kept.'
            : 'Failed: ${_live?['error'] ?? 'unknown error'}. Nothing below the snapshot point was lost.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.note(msg),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ]),
    );
  }

  Widget _planView(ReaderUi ui) {
    final sections = _plan!['sections'] as List? ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.note(
          'Each section can be split (moved out of this document — a snapshot is kept) or copied (this document stays intact).'),
      const SizedBox(height: 12),
      ...sections.map((s) => _sectionRow(ui, s)),
      const SizedBox(height: 16),
      if (_confirming)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ui.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ui.primary.withValues(alpha: 0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Split removes those sections from this document. A snapshot of the original is kept, but the document itself will change. Continue?',
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.critical),
            ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton(
                  onPressed: _execute, child: const Text('Yes, reorganize')),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: () => setState(() => _confirming = false),
                  child: const Text('Go back')),
            ]),
          ]),
        )
      else
        Row(children: [
          FilledButton(
            onPressed: _ops.isEmpty
                ? null
                : () => _hasSplit
                    ? setState(() => _confirming = true)
                    : _execute(),
            child: Text(
                'Reorganize ${_ops.length} section${_ops.length == 1 ? '' : 's'}'),
          ),
          const SizedBox(width: 8),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
        ]),
    ]);
  }

  Widget _sectionRow(ReaderUi ui, dynamic s) {
    final c = _choices[s['section_id']]!;
    final dests = s['destinations'] as List? ?? [];
    final mode = c.mode ?? _defaultMode;
    final chunkCount = (s['chunk_ids'] as List? ?? []).length;
    return Opacity(
      opacity: c.include ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ui.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              value: c.include,
              onChanged: (v) => setState(() => c.include = v ?? false),
              activeColor: ui.primary,
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['title'] ?? 'Section',
                        style: TextStyle(fontFamily: 'Geist', 
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ui.fg)),
                    Text('${s['summary'] ?? ''} · $chunkCount passage${chunkCount == 1 ? '' : 's'}',
                        style:
                            TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
                  ]),
            ),
          ]),
          if (c.include && dests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: c.destKey,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.fg),
                    dropdownColor: ui.card,
                    items: dests
                        .map<DropdownMenuItem<String>>((d) => DropdownMenuItem(
                              value: _destKey(d),
                              child: Text(
                                  '${d['kind'] == 'folder' ? '📁 ' : '📄 '}${_destLabel(d)} · ${_pct(d['confidence'])}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => c.destKey = v),
                  ),
                  _modeToggle(ui, c, mode),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  Widget _modeToggle(ReaderUi ui, _Choice c, String mode) {
    Widget seg(String label, String value) {
      final on = mode == value;
      return GestureDetector(
        onTap: () => setState(() => c.mode = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: on ? ui.primary : Colors.transparent,
          child: Text(label,
              style: TextStyle(fontFamily: 'Geist', 
                  fontSize: 12, color: on ? ui.accentFg : ui.muted)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ui.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Split', 'split'),
        seg('Copy', 'copy'),
      ]),
    );
  }
}
