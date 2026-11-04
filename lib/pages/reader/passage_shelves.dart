import 'package:flutter/material.dart';

import '../../models/tag.dart';
import '../../services/api.dart';
import '../../services/error_text.dart';
import '../../widgets/kit/kit.dart';
import '../tags/shelf_sheet.dart';
import 'chunk_shelves.dart';

/// One passage's shelves in edit mode (contract 2.35.0, ADR-034; §35 in D;
/// web `ManuscriptPanel` `ChunkShelves`). TODO L265: until round 2 this client
/// had the rule ([effectiveChunkShelves]) and drew nothing from it.
///
/// A passage INHERITS its document's shelves; `tag_overrides {added, removed}`
/// is the reader's intent on top, and the effective set is computed at read:
/// `(doc.tag_ids − removed) ∪ added`, inherited chips first and quiet, added
/// ones after. Each toggle replaces THIS passage's override wholesale through
/// `fn_update_chunk_tags`, and nothing moves until the write is accepted
/// (write before move): the editor is busy meanwhile, and a refusal is its
/// §14.2 line. A passage-level shelf never files the document; a dangling id
/// draws nothing and stays inert.
class PassageShelves extends StatefulWidget {
  final String docId;
  final String chunkId;
  final List<String> docTagIds;
  final List<Tag> shelves;

  /// What the last read (or this session's last accepted write) said.
  final Map<String, dynamic>? tagOverrides;

  /// The write was accepted: the host keeps `{added, removed}` as this
  /// passage's override from now on.
  final void Function(Map<String, dynamic> next) onSaved;

  const PassageShelves({
    super.key,
    required this.docId,
    required this.chunkId,
    required this.docTagIds,
    required this.shelves,
    required this.tagOverrides,
    required this.onSaved,
  });

  @override
  State<PassageShelves> createState() => _PassageShelvesState();
}

class _PassageShelvesState extends State<PassageShelves> {
  bool _busy = false;
  String? _error;

  Map<String, Tag> get _byId => {for (final s in widget.shelves) s.id: s};

  List<String> get _added => [
        for (final id
            in ((widget.tagOverrides?['added'] as List?) ?? const []).cast<String>())
          if (_byId.containsKey(id)) id,
      ];

  List<String> get _removed =>
      ((widget.tagOverrides?['removed'] as List?) ?? const []).cast<String>();

  Future<void> _write(List<String> added, List<String> removed) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.updateChunkTags(widget.docId, [
        chunkOverrideEntry(
            chunkId: widget.chunkId, added: added, removed: removed),
      ]);
      if (!mounted) return;
      widget.onSaved({'added': added, 'removed': removed});
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeSdkError(e);
      });
    }
  }

  void _drop(String id) {
    final added = _added, removed = _removed;
    if (added.contains(id)) {
      _write([for (final x in added) if (x != id) x], removed);
    } else {
      _write(added, [...removed, id]);
    }
  }

  void _put(String id) {
    final added = _added, removed = _removed;
    if (removed.contains(id)) {
      _write(added, [for (final x in removed) if (x != id) x]);
    } else {
      _write([...added, id], removed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byId = _byId;
    final removed = _removed;
    final added = _added;
    final inherited = [
      for (final id in widget.docTagIds)
        if (byId.containsKey(id) && !removed.contains(id)) id,
    ];
    final effective = effectiveChunkShelves(
        widget.docTagIds, {'added': added, 'removed': removed}).toSet();
    return KitShelfChipEditor(
      chips: [
        for (final id in inherited) KitShelfChip(byId[id]!, inherited: true),
        for (final id in added)
          if (!inherited.contains(id)) KitShelfChip(byId[id]!),
      ],
      addable: [
        for (final s in widget.shelves)
          if (!effective.contains(s.id)) s,
      ],
      allShelves: widget.shelves,
      busy: _busy,
      error: _error,
      removeLabel: (s) => 'Take this passage off ${s.title}',
      onAdd: _put,
      onRemove: _drop,
      onCreate: (name) => showShelfSheet(
        context,
        canBackfill: true,
        land: null,
        initialName: name,
        createSubtitle: 'This passage goes on it as soon as it is created.',
        onCreated: _put,
      ),
    );
  }
}
