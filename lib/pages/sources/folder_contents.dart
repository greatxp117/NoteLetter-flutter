import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/api_service.dart' show ApiException;
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// What is inside ONE folder, on demand (4.59.0, ADR-096) —
/// `screens/sources.md` §Folder contents; web `FolderContents` in
/// `CloudFilePicker.jsx`.
///
/// **Never mounted open.** The row carries a collapsed "What's in here?" and
/// the scan runs only when the reader opens it: fifteen visible folders
/// scanned on open would be three hundred provider calls. A scanned row stays
/// open and is not re-scanned.
///
/// The figures are the folder's CONTENTS, not the outcome of an import — the
/// scan does not dedupe against files already imported, so nothing here says
/// "will be imported". And the two unimported buckets stay apart:
/// `excluded_by_settings` is a setting (pptx is off by default, so a folder of
/// decks is one toggle from working), `unreadable` is a fact with nothing to
/// do. Merging them is the defect the section exists to prevent.
class FolderContents extends StatefulWidget {
  final String provider;
  final String folderId;

  /// The *Import these types* control, where the host has one to point at.
  final VoidCallback? onFixTypes;

  /// The request, injectable so the rendering is testable without a network.
  final Future<Map<String, dynamic>> Function()? scan;

  const FolderContents({
    super.key,
    required this.provider,
    required this.folderId,
    this.onFixTypes,
    this.scan,
  });

  @override
  State<FolderContents> createState() => _FolderContentsState();
}

/// Both halves of the type vocabulary: a key the scan returns that this map
/// does not name falls back to its upper-case spelling rather than vanishing.
const _typeLabel = {
  'pdf': 'PDF',
  'docx': 'Word',
  'pptx': 'PowerPoint',
  'notion': 'Notion page',
};

/// A cloud type key as the reader reads it — web `cloudTypeLabel`
/// (CloudFilePicker.jsx): the sync settings' type chips and rule rows and the
/// folder scan all spell `docx` "Word" and `pptx` "PowerPoint".
String cloudTypeLabel(String key) => _typeLabel[key] ?? key.toUpperCase();

String spellTypes(Object? counts) {
  if (counts is! Map) return '';
  final entries = [
    for (final e in counts.entries)
      if (e.value is num && (e.value as num) > 0)
        MapEntry(e.key.toString(), (e.value as num).toInt()),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return entries
      .map((e) => '${e.value} ${cloudTypeLabel(e.key)}')
      .join(' · ');
}

class _FolderContentsState extends State<FolderContents> {
  bool _open = false;
  bool _busy = false;
  Map<String, dynamic>? _scan;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _open = true;
      _busy = true;
      _error = null;
    });
    try {
      final data = await (widget.scan?.call() ??
          Api.instance
              .scanCloudFolder(widget.provider, folderId: widget.folderId));
      if (!mounted) return;
      setState(() => _scan = data);
    } on ApiException catch (e) {
      // A hole, never a zero: "nothing readable" for a scan that did not
      // complete is the one thing this surface is against (kit §14.2).
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read this folder.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return KitSettingLink('What’s in here?', icon: null, onTap: _run);
    }
    final t = Tokens.of(context);
    TextStyle note(double size) =>
        KitText.lede(context, fontSize: size, height: size * 1.5)
            .copyWith(color: t.fgSubtle);
    final s = _scan;
    final children = <Widget>[];

    if (_busy) {
      children.add(Text('Counting…', style: note(12)));
    } else if (_error != null) {
      children
        ..add(KitFailureInline(_error!, dense: true))
        ..add(KitSettingLink('Try again', icon: null, onTap: _run));
    } else if (s != null) {
      final scanned = (s['scanned'] as Map?) ?? const {};
      final files = (scanned['files'] as num?)?.toInt() ?? 0;
      final depth = (scanned['depth'] as num?)?.toInt() ?? 0;
      final complete = s['complete'] != false;
      final floor = complete ? '' : 'at least ';
      final readable = spellTypes(s['importable']);
      final excluded = spellTypes(s['excluded_by_settings']);
      final byPattern = (s['excluded_by_pattern'] as num?)?.toInt() ?? 0;
      final unreadable = (s['unreadable'] as num?)?.toInt() ?? 0;
      final held = (s['held_for_review'] as num?)?.toInt() ?? 0;

      children.add(Text(
        'scanned $files file${files == 1 ? '' : 's'}'
        '${depth > 0 ? ', ${depth + 1} levels' : ''}',
        style: note(11),
      ));
      // "Nothing … can read" is for a folder with nothing readable at all.
      // Said over a folder of decks the settings exclude it is the very merge
      // §Folder contents forbids — they ARE readable, one toggle away — so
      // there the excluded line below speaks alone.
      if (readable.isNotEmpty || (excluded.isEmpty && byPattern == 0)) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            readable.isNotEmpty
                ? '$floor$readable'
                : 'Nothing in here NoteLetter can read.',
            style: KitText.ui(context),
          ),
        ));
      }
      if (held > 0) {
        children.add(Text('…$held will wait for your review', style: note(12)));
      }
      if (excluded.isNotEmpty || byPattern > 0) {
        // A setting, so it carries its control.
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                [
                  if (excluded.isNotEmpty) '$excluded excluded by your settings',
                  if (byPattern > 0) '$byPattern excluded by your patterns',
                ].join(' · '),
                style: note(12),
              ),
              if (widget.onFixTypes != null && excluded.isNotEmpty)
                KitSettingLink('Change types',
                    icon: null, onTap: widget.onFixTypes),
            ],
          ),
        ));
      }
      if (unreadable > 0) {
        // A fact, so it carries no affordance — there is nothing to do.
        children.add(Text('$unreadable NoteLetter can’t read', style: note(12)));
      }
      if (!complete) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('counted $files of more — open it to see the rest',
              style: note(11)),
        ));
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
