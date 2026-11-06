import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../models/upload_file.dart';
import '../pages/sources/sources_info_sheet.dart';
import '../services/resumable_upload.dart';
import '../shared/chosen_shelves.dart';
import '../shared/cloud_return.dart';
import '../shared/playlist.dart';
import '../shared/upload_types.dart';
import '../state/cloud_notifier.dart';
import '../state/upload_notifier.dart';
import 'add_shelves.dart';
import 'kit/kit.dart';

/// **Quick add** — *Add to your library* (F-152; web `overlays/QuickAdd.jsx`).
///
/// A sheet over the current page, never a route (component-kit §15's add
/// sheet, 540 wide, 82% tall): the zone (*Drop files, or tap to add one* —
/// touch copy — and the accepted kinds), the one-source question when 2+
/// images come in one pick (5.10.0, ADR-170), the link row, this client's
/// *Add an image set* row, kit §20.3's shelves (5.73.0, ADR-238), what this
/// opening is sending (*Going to your library*), *Or connect a service* with
/// the four providers, and the foot:
/// *What can I add?* and *More options →* (Add a source, `/sources/add`).
///
/// Opened by the same buttons as on web: Home's and the Library's *Add a
/// source*, the tab bar's default *Add*, Home's checklist *Add your first
/// source*, and an empty Home's *Paste a link* and drop zone (which picks
/// first and opens it already filing — [pickThenShow]). On a phone it rises
/// from the foot and a swipe closes it; wider it is web's dialog.
///
/// One upload path: every file, link and set goes through [UploadNotifier]
/// (the Library's and Add a source's intake), which outlives the sheet — a
/// closed sheet stops nothing that has started. Each row is the notifier's
/// own row, found by the id it was made under; a refusal at the door has no
/// row there and is drawn here with its reason. *Connect* is the app's one
/// connect entry point ([CloudNotifier.connect], F-151) — awaited, and only
/// a return that came back closes the sheet: the app opens the connect page
/// for it, its own route over the Library (5.52.0, ADR-203, `ConnectOnReturn`).
class QuickAdd extends StatefulWidget {
  /// Files picked before the sheet opened (an empty Home's drop zone), filed
  /// exactly as if they had been picked here.
  final List<PlatformFile> seed;

  /// *More options →* — close, then Add a source.
  final VoidCallback onMore;

  /// A connect whose session came back with a return: close. The app opens
  /// the connect page, which spends it.
  final VoidCallback onReturn;

  const QuickAdd({
    super.key,
    this.seed = const [],
    required this.onMore,
    required this.onReturn,
  });

  static const title = 'Add to your library';
  static const subtitle = 'Drop a file, paste a link, or connect a service.';

  /// The four services, by the backend's provider ids (sources.md §Data; web
  /// `QA_CONNECTORS` — a non-canonical id once made connect 400).
  static const connectors = [
    (id: 'google_drive', name: 'Google Drive'),
    (id: 'onedrive', name: 'OneDrive'),
    (id: 'notion', name: 'Notion'),
    (id: 'dropbox', name: 'Dropbox'),
  ];

  /// Open quick add over the page that owns [context].
  static Future<void> show(BuildContext context,
      {List<PlatformFile> seed = const []}) {
    final router = GoRouter.maybeOf(context);
    return KitOverlaySheet.show(
      context,
      icon: KitQuill.icon,
      title: title,
      subtitle: subtitle,
      width: 540,
      heightFactor: 0.82,
      phoneSheet: true,
      foot: Builder(
        builder: (ctx) => KitQaFoot(
          onHelp: () => SourcesInfoSheet.show(ctx),
          onMore: () {
            Navigator.of(ctx).pop();
            router?.go('/sources/add');
          },
        ),
      ),
      builder: (ctx) => QuickAdd(
        seed: seed,
        onMore: () {
          Navigator.of(ctx).pop();
          router?.go('/sources/add');
        },
        onReturn: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  /// An empty Home's drop zone (web `FirstSources` → `addFiles`): the picker
  /// first, then quick add already filing what was picked. A cancelled pick
  /// opens nothing.
  static Future<void> pickThenShow(BuildContext context) async {
    final picked = await pickFiles();
    if (picked == null || picked.isEmpty || !context.mounted) return;
    await show(context, seed: picked);
  }

  /// The zone's picker: the contracted set (4.10.0, ADR-046), advisory — every
  /// file still meets `uploadRejection`. On a device each file is read from its
  /// path a slice at a time as it uploads (F-121); a web pick carries bytes.
  static Future<List<PlatformFile>?> pickFiles() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: uploadAllowedExtensions,
    );
    return r?.files;
  }

  @override
  State<QuickAdd> createState() => _QuickAddState();
}

/// One source this opening is sending. [rowId] is the notifier's row once it
/// exists; [refusal] is a refusal at the door, which makes no row.
class _Item {
  _Item(this.name, this.kind, {this.playlist = false});
  final String name;
  final String kind;
  final bool playlist;
  String? rowId;
  String? refusal;
}

class _QuickAddState extends State<QuickAdd> {
  final _link = TextEditingController();
  final _linkFocus = FocusNode();

  /// Newest first, as web prepends.
  final List<_Item> _items = [];

  /// 2+ images from one pick, waiting for the one-source question. Closing
  /// the sheet abandons them — nothing has been sent.
  List<PlatformFile>? _setChoice;

  String? _connectBusy;
  ({String id, String message})? _connectFail;

  /// Kit §20.3: for this opening. Each opening is its own state, so closing
  /// drops it, and a seed goes in before anything can be chosen.
  final _chosen = ChosenShelves();

  @override
  void initState() {
    super.initState();
    if (widget.seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _take(widget.seed);
      });
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _linkFocus.dispose();
    _chosen.dispose();
    super.dispose();
  }

  UploadNotifier get _upload => context.read<UploadNotifier>();

  static String _mime(PlatformFile f) =>
      lookupMimeType(f.name) ?? 'application/octet-stream';

  Future<void> _pick() async {
    final picked = await QuickAdd.pickFiles();
    if (picked == null || picked.isEmpty || !mounted) return;
    _take(picked);
  }

  /// A pick: 2+ images wait for the question, everything else goes now, one
  /// by one. A second pick while the question is open joins the first.
  void _take(List<PlatformFile> files) {
    final images = <PlatformFile>[];
    final rest = <PlatformFile>[];
    for (final f in files) {
      (isSetImage(name: f.name, size: f.size, mimeType: _mime(f))
              ? images
              : rest)
          .add(f);
    }
    if (images.length < 2) {
      files.forEach(_addFile);
      return;
    }
    rest.forEach(_addFile);
    setState(() => _setChoice = [...?_setChoice, ...images]);
  }

  void _addFile(PlatformFile f) {
    final mime = _mime(f);
    final item = _Item(f.name, kitDocKind(mime.contains('pdf') ? 'pdf' : 'note'));
    setState(() => _items.insert(0, item));
    // The same words the server would use, without the round trip; the server
    // still decides, and its message still reaches the row.
    final refused = uploadRejection(name: f.name, size: f.size, mimeType: mime);
    final bytes = f.bytes;
    final path = kIsWeb ? null : f.path;
    if (refused != null || (bytes == null && path == null)) {
      setState(() => item.refusal = refused ?? 'Upload failed.');
      return;
    }
    unawaited(_upload.addFile(f.name, f.size, bytes, mime,
        source: path == null ? null : ChunkSource.file(path, f.size),
        onRow: (id) => item.rowId = id,
        tagIds: _chosen.ids));
  }

  void _separate() {
    final images = _setChoice ?? const <PlatformFile>[];
    setState(() => _setChoice = null);
    images.forEach(_addFile);
  }

  /// *One source*: one image set, its pages oldest first then by natural
  /// filename (sources.md §Endpoints used).
  Future<void> _oneSource() async {
    final frames = orderFrames(_setChoice ?? const <PlatformFile>[],
        name: (f) => f.name,
        lastModified: (f) => fileModifiedMs(kIsWeb ? null : f.path));
    setState(() => _setChoice = null);
    await _sendSet(frames);
  }

  /// *Add an image set*: the device's own picker (Photos on a phone), one set
  /// of up to 20, never asked — as on Add a source.
  Future<void> _pickImageSet() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (r == null || r.files.isEmpty || !mounted) return;
    await _sendSet(r.files.take(kImageSetMax).toList());
  }

  Future<void> _sendSet(List<PlatformFile> frames) async {
    if (frames.isEmpty) return;
    // Taken now, before the frames are read: the row stays live meanwhile.
    final tagIds = _chosen.ids;
    final item = _Item('${frames.length} images — one source', 'note');
    setState(() => _items.insert(0, item));
    final images =
        <({String name, int size, Uint8List bytes, String mimeType})>[];
    try {
      for (final f in frames) {
        final bytes = f.bytes ??
            await ChunkSource.file(f.path!, f.size).read(0, f.size);
        images.add((
          name: f.name,
          size: f.size,
          bytes: bytes,
          mimeType: imageMimeOf(f.name, _mime(f)) ?? 'image/jpeg',
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => item.refusal = 'Image upload failed. Please try again.');
      }
      return;
    }
    if (!mounted) return;
    await _upload.addImageSet(images,
        onRow: (id) => item.rowId = id, tagIds: tagIds);
  }

  Future<void> _addLink() async {
    final v = _link.text.trim();
    if (v.isEmpty) return;
    final type = detectUrlType(v);
    final bare = v.replaceFirst(RegExp(r'^https?://'), '');
    final item = _Item(bare.length <= 44 ? bare : bare.substring(0, 44),
        pendingBadgeKind(type ?? 'article'),
        playlist: type == playlistType);
    setState(() => _items.insert(0, item));
    _link.clear();
    final rejection = await _upload.addUrl(v,
        onRow: (id) => item.rowId = id, tagIds: _chosen.ids);
    // A link refused at the door makes no row: its reason is said here.
    if (mounted && rejection != null && item.rowId == null) {
      setState(() => item.refusal = rejection);
    }
  }

  Future<void> _connect(String id) async {
    setState(() {
      _connectBusy = id;
      _connectFail = null;
    });
    final err = await context.read<CloudNotifier>().connect(id);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _connectBusy = null;
        _connectFail = (id: id, message: err);
      });
      return;
    }
    // The app's session came back with a return (5.1.0, ADR-159): the connect
    // page, opened over the Library, is where it is spent and answered.
    if (CloudReturn.pending.value != null) {
      widget.onReturn();
      return;
    }
    // A web build has left for the provider: the chip stays busy, as web's.
    if (!CloudReturn.appReturn) return;
    // A cancelled session parked nothing: the chip can be pressed again.
    setState(() => _connectBusy = null);
  }

  KitQaRow _row(
      _Item it, Map<String, UploadFile> byId, Map<String, double> put) {
    final f = it.rowId == null ? null : byId[it.rowId];
    final KitQaState state;
    if (f == null) {
      state = it.refusal != null ? KitQaState.error : KitQaState.uploading;
    } else {
      state = switch (f.status) {
        UploadStatus.completed => KitQaState.filed,
        UploadStatus.error => KitQaState.error,
        UploadStatus.uploading || UploadStatus.pending => KitQaState.uploading,
      };
    }
    final frac = f?.docId == null ? null : put[f!.docId];
    final pct = frac == null ? null : (frac * 100).round();
    final line = switch (state) {
      KitQaState.uploading =>
        '${it.playlist ? '$playlistLabel — ' : ''}'
            '${pct == null ? 'uploading…' : 'uploading… $pct%'}',
      KitQaState.error => f?.errorMessage ?? it.refusal ?? 'failed to add',
      KitQaState.filed => f?.note ?? 'added — indexing will begin shortly',
    };
    return KitQaRow(
      kind: it.kind,
      name: it.name,
      line: line,
      state: state,
      pct: state == KitQaState.uploading ? pct : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final upload = context.watch<UploadNotifier>();
    final byId = {for (final f in upload.files) f.id: f};
    final put = upload.uploadFractions;
    final rows = [for (final it in _items) _row(it, byId, put)];
    final ready = rows.where((r) => r.state == KitQaState.filed).length;
    final fail = _connectFail;
    final failName = fail == null
        ? null
        : QuickAdd.connectors
            .where((c) => c.id == fail.id)
            .map((c) => c.name)
            .firstOrNull;
    // A keyboard comes up uninvited on a touch device; web focuses the field
    // on open, which a desktop build keeps.
    final focusOnOpen = kIsWeb ||
        const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}
            .contains(defaultTargetPlatform);

    return KitQaBody(children: [
      KitQaHang(
        // The body's 14, as web's flex gap; the question adds its own 12.
        gap: 14,
        below: _setChoice == null
            ? null
            : KitImageSetChoice(
                count: _setChoice!.length,
                onOne: _oneSource,
                onSeparate: _separate,
              ),
        child: KitDropZone(
          compact: true,
          icon: KitUploadGlyph.icon,
          title: 'Drop files, or tap to add one',
          help: uploadAcceptHelp,
          onTap: _pick,
        ),
      ),
      KitQaHang(
        gap: 4,
        // The device capability web lacks (Flutter CLAUDE.md).
        below: KitImageSetRow(onPressed: _pickImageSet),
        child: KitQaLinkRow(
          controller: _link,
          focusNode: _linkFocus,
          autofocus: focusOnOpen,
          onSubmit: _addLink,
        ),
      ),
      AddShelves(chosen: _chosen),
      if (rows.isNotEmpty) KitQaAdded(ready: ready, rows: rows),
      const KitQaOr('or connect a service'),
      KitQaHang(
        below: fail == null
            ? null
            : KitFailureInline('${failName ?? 'That service'} — ${fail.message}',
                dense: true),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in QuickAdd.connectors)
              KitQaChip(
                provider: c.id,
                name: c.name,
                busy: _connectBusy == c.id,
                onTap: () => _connect(c.id),
              ),
          ],
        ),
      ),
    ]);
  }
}
