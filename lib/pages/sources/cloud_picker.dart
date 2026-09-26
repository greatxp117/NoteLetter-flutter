import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'folder_contents.dart';

/// The parts of web's ONE `CloudFilePicker` (`screens/sources.md`), shared by
/// both of this client's hosts: the import picker (mode `import`, F-61) and
/// the sync-folder chooser (mode `folders`, F-67). They were two compositions
/// once, and the second kept the boxed rows and caps crumbs the first had
/// shed — so the frame, the crumb row, the checkbox, the folder row and the
/// foot live here, and each host supplies only its state and its words.

/// The panel: `--bg-2` (= `--surface-raised`), r-lg, padding 14, a border.
/// No title row and no close control — Cancel is the way out.
class CloudPickerPanel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  const CloudPickerPanel({
    super.key,
    required this.children,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// The crumbs as `.set-link`s (`Root` › …), the current one inert, with the
/// selection counter as a `.proc-note` at the right of the same row.
class CloudPickerCrumbs extends StatelessWidget {
  final List<String> labels;
  final void Function(int index) onJump;
  final String counter;

  const CloudPickerCrumbs({
    super.key,
    required this.labels,
    required this.onJump,
    required this.counter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < labels.length; i++)
                  KitSettingLink(
                    labels[i],
                    icon: i < labels.length - 1 ? Icons.chevron_right : null,
                    onTap: i == labels.length - 1 ? null : () => onJump(i),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          KitProcNote(counter, padding: EdgeInsets.zero),
        ],
      ),
    );
  }
}

/// A row's checkbox, 20×20. [value] null keeps the slot's width with no box
/// — a file the import would refuse is offered no checkbox, and the row still
/// lines up with its neighbours.
class CloudPickerCheck extends StatelessWidget {
  final bool? value;

  /// The action the confirm names — `Import …`, `Sync …`.
  final String label;
  final VoidCallback onToggle;

  const CloudPickerCheck({
    super.key,
    required this.value,
    required this.label,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SizedBox(
      width: 20,
      height: 20,
      child: value == null
          ? null
          : Semantics(
              label: label,
              child: Checkbox(
                value: value,
                onChanged: (_) => onToggle(),
                activeColor: t.accent,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
    );
  }
}

/// A folder row, unboxed: the checkbox, then the `.set-link` name and chevron
/// (navigates in) with §Folder contents on its disclosure beneath (4.59.0,
/// ADR-096) — never scanned eagerly.
class CloudPickerFolderRow extends StatelessWidget {
  final CloudPickerCheck check;
  final String name;
  final VoidCallback onOpen;
  final String provider;
  final String folderId;
  final VoidCallback? onFixTypes;
  final Future<Map<String, dynamic>> Function()? scan;

  const CloudPickerFolderRow({
    super.key,
    required this.check,
    required this.name,
    required this.onOpen,
    required this.provider,
    required this.folderId,
    this.onFixTypes,
    this.scan,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        check,
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KitSettingLink(name, onTap: onOpen),
              FolderContents(
                key: ValueKey('scan-$folderId'),
                provider: provider,
                folderId: folderId,
                onFixTypes: onFixTypes,
                scan: scan,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `Load more…`, a bare link under the rows.
class CloudPickerLoadMore extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const CloudPickerLoadMore({
    super.key,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: KitSettingLink(
        loading ? 'Loading…' : 'Load more…',
        icon: null,
        onTap: loading ? null : onTap,
      ),
    ),
  );
}

/// The foot: the confirm (primary, naming what it does and how many) beside
/// a quiet Cancel. [onConfirm] null disables it; [busy] disables Cancel too.
class CloudPickerFoot extends StatelessWidget {
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;
  final bool busy;

  const CloudPickerFoot({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        KitButton.primary(confirmLabel, onPressed: busy ? null : onConfirm),
        KitButton.ghost('Cancel', onPressed: busy ? null : onCancel),
      ],
    ),
  );
}
