import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../state/documents_notifier.dart';
import '../state/tags_notifier.dart';
import '../state/upload_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/file_uploader.dart';
import '../widgets/kit/kit.dart';
import 'sources/browse_section.dart' show ProcessingList;
import 'sources/source_facets.dart';
import 'sources/sources_info_sheet.dart';

/// **Add a source** — route `/sources/add` (`screens/sources.md` §Composition,
/// *Add a source*; web `AddSource.jsx`): the drop zone and the link row in the
/// column, what the library takes on the sheet, and **Just added** — what this
/// visit created, READ FROM THE DOCUMENTS SUBSCRIPTION (never a timer: the
/// prototype's rows are simulated). A document the subscription has not
/// delivered yet is not drawn: its own arrival is the statement.
///
/// The Library's *Add a source*, the tab bar's *Add* and Home's *Add files*
/// come here — this client has no quick-add overlay. Home's *Add files* sends
/// [pick], which opens the file picker once on arrival.
class AddSourcePage extends StatefulWidget {
  final bool pick;

  const AddSourcePage({super.key, this.pick = false});

  /// The standfirst, verbatim from the reference.
  static const stand = 'Upload anything you’ve read, paste a link, or connect '
      'a service. NoteLetter parses the text, splits it into passages, and '
      'embeds each one for search.';

  @override
  State<AddSourcePage> createState() => _AddSourcePageState();
}

class _AddSourcePageState extends State<AddSourcePage> {
  final _uploader = GlobalKey<FileUploaderState>();

  /// Where the intake's created ids stood when this visit began: the ones
  /// after it are this visit's.
  late final int _mark;

  @override
  void initState() {
    super.initState();
    _mark = context.read<UploadNotifier>().addedMark;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DocumentsNotifier>().start();
      context.read<TagsNotifier>().start();
      // A page arriving starts with nothing answered (web: a new intake).
      context.read<UploadNotifier>().clearAnswered();
      if (widget.pick) _uploader.currentState?.pickFiles();
    });
  }

  void _library() => context.go('/sources');

  // A Reader opened from here returns here (ADR-101, `shell/backOrigin.js`).
  void _open(Document d) => context.push(KitSourceLink.readerHref(
      d.id, 'from=${Uri.encodeComponent('/sources/add')}'));

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    final tags = context.watch<TagsNotifier>();
    final upload = context.watch<UploadNotifier>();
    final dark = Tokens.of(context).isDark;

    final byId = {for (final d in docs.documents) d.id: d};
    final added = [
      for (final id in upload.addedSince(_mark).reversed)
        if (byId[id] != null) byId[id]!,
    ];
    final ready =
        added.where((d) => d.status == DocumentStatus.complete).toList();
    final reading =
        added.where((d) => d.status != DocumentStatus.complete).toList();
    final homeOf = kitShelfModel(tags.tags, docs.documents).homeOf;

    return KitDPage(
      back: KitDBackControl('The library', onTap: _library),
      folio: 'The library · Add a source',
      title: 'Add to Your Library',
      stand: AddSourcePage.stand,
      sheet: KitDSheet(
        label: 'What you can add',
        peek: KitLibPeek(
          icon: KitUploadGlyph.icon,
          title: added.isEmpty ? 'What you can add' : 'Just added',
          count: added.isEmpty ? null : '${ready.length}',
          tail: added.isEmpty ? null : ' of ${added.length} ready',
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('What you can add', first: true),
            KitFigures(rows: kAddable),
            if (added.isNotEmpty) ...[
              const KitDLabel('Just added'),
              KitFigures(rows: [
                ('Ready', kitThousands(ready.length)),
                ('Being read', kitThousands(reading.length)),
              ]),
            ],
            KitSheetAlso(children: [
              KitAlsoButton('Go to the library',
                  icon: Icons.menu_book_outlined, onTap: _library),
              KitAlsoButton('What can I add?',
                  icon: Icons.help_outline,
                  onTap: () => SourcesInfoSheet.show(context)),
            ]),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The drop zone (touch copy: *tap*), the link row, the device's
          // image-set row, and what adding answered — this client's one
          // upload path.
          FileUploader(key: _uploader, look: FileUploaderLook.add),
          if (added.isNotEmpty) ...[
            // `.dp-just{margin-top:56px}`.
            const SizedBox(height: 56),
            KitSectionHead(
              'Just added',
              small: true,
              meta: '${ready.length} of ${added.length} ready',
              actions: [KitHxLink('Go to library →', onTap: _library)],
            ),
            if (reading.isNotEmpty)
              ProcessingList(
                items: reading,
                uploadPcts: upload.uploadFractions,
              ),
            if (reading.isNotEmpty && ready.isNotEmpty)
              const SizedBox(height: 8),
            for (final d in ready)
              KitRegisterRow(
                key: ValueKey('just-${d.id}'),
                doc: d,
                shelfTitle: homeOf[d.id]?.title,
                shelfColor: AppColors.shelfColor(homeOf[d.id]?.color, dark: dark),
                onOpen: () => _open(d),
              ),
          ],
        ],
      ),
    );
  }
}
