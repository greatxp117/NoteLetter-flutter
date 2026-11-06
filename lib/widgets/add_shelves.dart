import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/tag.dart';
import '../pages/tags/shelf_sheet.dart';
import '../services/api.dart';
import '../shared/chosen_shelves.dart';
import '../state/documents_notifier.dart';
import '../state/tags_notifier.dart';
import 'kit/kit.dart';

/// Kit §20.3 on the app's own surfaces (5.73.0, ADR-238): [KitAddShelves] over
/// the tags subscription, its create row opening the app's own form (§20.1). The
/// three hosts — quick add, Add a source and `/share` — each hold a
/// [ChosenShelves] and read `ids` when an add is pressed.
///
/// The read starts here, not in the host. A host can be up with no reader (a
/// share signed out, which draws no row), and [TagsNotifier.start] with no reader
/// answers empty and is never asked again, so a later sign-in would read nothing.
class AddShelves extends StatefulWidget {
  final ChosenShelves chosen;
  final bool disabled;
  final bool fillPhone;

  const AddShelves({
    super.key,
    required this.chosen,
    this.disabled = false,
    this.fillPhone = false,
  });

  @override
  State<AddShelves> createState() => _AddShelvesState();
}

class _AddShelvesState extends State<AddShelves> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
      // Whether the form offers to fill the shelf (library.md §Creating a shelf).
      context.read<DocumentsNotifier>().start();
    });
  }

  /// `fn_create_tag`, and the new shelf on the row the moment it resolves, with
  /// what the form knows: the reader stays here, and the read will bring the rest.
  Future<Map<String, dynamic>> _create(String title,
      {String? description, String? color, String? parentTagId}) async {
    final answer = await Api.instance.createTag(title,
        description: description, color: color, parentTagId: parentTagId);
    final id = answer['tagId'] as String?;
    if (mounted && id != null && id.isNotEmpty) {
      widget.chosen.addMade(Tag(
        id: id,
        userId: '',
        title: title,
        description: description,
        color: color,
        documentCountStored: false,
        parentTagId: parentTagId,
      ));
    }
    return answer;
  }

  @override
  Widget build(BuildContext context) {
    final tags = context.watch<TagsNotifier>().tags;
    return KitAddShelves(
      chosen: widget.chosen,
      shelves: tags,
      disabled: widget.disabled,
      fillPhone: widget.fillPhone,
      onCreate: (name) => showShelfSheet(
        context,
        canBackfill: context
            .read<DocumentsNotifier>()
            .documents
            .any((d) => d.status == DocumentStatus.complete),
        land: null,
        initialName: name,
        createSubtitle: KitAddShelves.createSubtitle,
        create: _create,
      ),
    );
  }
}
