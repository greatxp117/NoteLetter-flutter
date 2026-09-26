import 'package:flutter/material.dart';

import '../../models/cloud_file.dart';
import '../../services/api.dart';
import '../../services/api_service.dart' show ApiException;
import '../../widgets/kit/kit.dart';
import 'cloud_picker.dart';

/// The sync-folder chooser — the cloud picker in **folders-only** mode
/// (`screens/sources.md` §Sync control: "reuse the file picker in folders-only
/// mode, ≤20"; web `CloudFilePicker mode="folders"` as `SyncSettingsPanel`
/// mounts it).
///
/// One selection pool, folders only: the listing is `fn_list_cloud_files`
/// with its files filtered out, and every folder row carries §Folder contents
/// (4.59.0, ADR-096) — this chooser lists no files at all, so a folder's name
/// was everything the reader had to go on.
///
/// The selection here is a DRAFT. Nothing on the panel moves until
/// [onConfirm] has been answered: the chips render the returned `integration`
/// and nothing else (write before move). A refused save keeps this picker open
/// with the server's sentence inline (§14.2), so the reader's choice is still
/// on screen to correct — closing it would throw away the one thing they did.
class SyncFolderPicker extends StatefulWidget {
  final String provider;

  /// The stored `sync_config.folder_ids` — the selection the picker opens on.
  final List<String> initial;

  /// `fn_sync_settings` validates `folder_ids` at ≤20.
  final int cap;

  /// Saves the whole list; answers null on success or the sentence to show.
  final Future<String?> Function(List<String> ids) onConfirm;
  final VoidCallback onCancel;

  /// Whether an empty list may be saved when folders were saved before —
  /// unticking every one clears the scope (web `allowEmpty`).
  final bool allowEmpty;

  /// The *Import these types* control, for §Folder contents' "Change types".
  final VoidCallback? onFixTypes;

  /// The listing request, injectable so the picker is testable without a
  /// network. Defaults to [Api.listCloudFiles].
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> params)?
  list;

  /// The scan behind each row's disclosure, injectable for the same reason.
  final Future<Map<String, dynamic>> Function(String folderId)? scan;

  const SyncFolderPicker({
    super.key,
    required this.provider,
    required this.initial,
    required this.onConfirm,
    required this.onCancel,
    this.cap = 20,
    this.allowEmpty = false,
    this.onFixTypes,
    this.list,
    this.scan,
  });

  @override
  State<SyncFolderPicker> createState() => _SyncFolderPickerState();
}

class _SyncFolderPickerState extends State<SyncFolderPicker> {
  final List<({String? id, String name})> _stack = [(id: null, name: 'Root')];
  List<CloudFile> _items = const [];
  String? _pageToken;
  late final Set<String> _selected = {...widget.initial};
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _capNote;

  /// Which listing request is the current one. Navigating while a slow
  /// folder is still answering let that folder's rows land under the NEW
  /// crumb on web, and its page token then appended the old folder's page 2
  /// there too. Only the latest request may write the listing.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _folderId => _stack.last.id;

  Future<void> _load({bool append = false}) async {
    final seq = ++_seq;
    final token = append ? _pageToken : null;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        // A new folder starts with nothing of the last one's: no rows, no
        // token.
        _items = const [];
        _pageToken = null;
      }
    });
    final params = <String, dynamic>{'provider': widget.provider};
    if (_folderId != null) params['folderId'] = _folderId;
    if (token != null) params['pageToken'] = token;
    try {
      final data =
          await (widget.list?.call(params) ??
              Api.instance.listCloudFiles(params));
      if (!mounted || seq != _seq) return;
      final page = CloudFileListing.fromJson(data);
      setState(() {
        final folders = page.items.where((f) => f.isFolder);
        _items = append ? [..._items, ...folders] : folders.toList();
        _pageToken = page.nextPageToken;
      });
    } on ApiException catch (e) {
      if (mounted && seq == _seq) _fail(e.message, append);
    } catch (_) {
      if (mounted && seq == _seq) _fail('Could not list this folder.', append);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  /// A failed page keeps its token so "Load more" asks for it again; a failed
  /// folder has no listing, so it has no token to continue from.
  void _fail(String message, bool append) => setState(() {
    _error = message;
    if (!append) _pageToken = null;
  });

  void _enter(CloudFile f) {
    _stack.add((id: f.id, name: f.name));
    _load();
  }

  void _jump(int i) {
    _stack.removeRange(i + 1, _stack.length);
    _load();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.contains(id) && _selected.length >= widget.cap) {
        // At the cap a toggle no-ops WITH its reason — a checkbox that
        // silently refuses reads as broken.
        // "Import these first" is the import picker's advice: a folder
        // chooser imports nothing, so its way on is to give a slot back (web
        // f050fe2's sentence, verbatim).
        _capNote =
            '${widget.cap}-folder limit reached — untick one to choose '
            'another.';
        return;
      }
      _capNote = null;
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final String? err;
    try {
      err = await widget.onConfirm(_selected.toList());
    } catch (_) {
      // §18: the failure slot is required — a refusal with no sentence must
      // still leave one, or the button simply re-enables.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save these folders.';
        });
      }
      return;
    }
    if (!mounted) return;
    // On success the host closes this picker; on a refusal it stays, with
    // the sentence, and the draft the reader built.
    setState(() {
      _saving = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    // An empty folder list is a valid `folder_ids` (sources.md §Sync control;
    // the panel then draws its inert-state warning), so unticking every saved
    // folder is a save like any other — web `allowEmpty` (12daabd). With
    // nothing saved and nothing ticked there is nothing to change.
    final canConfirm =
        n > 0 || (widget.allowEmpty && widget.initial.isNotEmpty);

    return CloudPickerPanel(
      margin: const EdgeInsets.only(top: 10),
      children: [
        CloudPickerCrumbs(
          labels: [for (final c in _stack) c.name],
          onJump: _jump,
          counter: '$n/${widget.cap} folders selected',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(_error!),
          ),
        if (_capNote != null)
          KitProcNote(_capNote!, padding: const EdgeInsets.only(bottom: 8)),
        // ADR-026 §3: standing guidance on every rendered Notion listing —
        // Notion never reports what it withheld, so this is never phrased
        // as a finding about THIS connection.
        if (widget.provider == 'notion' && _error == null && !_loading)
          const KitProcNote(
            'Notion passes along only the pages you ticked — to bring '
            'more in, grant access in Notion and return.',
            padding: EdgeInsets.only(bottom: 8),
          ),
        for (final f in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CloudPickerFolderRow(
              key: ValueKey('sync-folder-${f.id}'),
              check: CloudPickerCheck(
                value: _selected.contains(f.id),
                label: 'Sync ${f.name}',
                onToggle: () => _toggle(f.id),
              ),
              name: f.name,
              onOpen: () => _enter(f),
              provider: widget.provider,
              folderId: f.id,
              onFixTypes: widget.onFixTypes,
              scan: widget.scan == null ? null : () => widget.scan!(f.id),
            ),
          ),
        // Empty is a CLAIM about a listing that answered (ADR-026 §2). Over
        // a failed request it is the §14 defect — a hole drawn as a zero.
        if (!_loading && _error == null && _items.isEmpty)
          const KitProcNote('No subfolders here.', padding: EdgeInsets.zero),
        if (_loading) const KitProcNote('Loading…', padding: EdgeInsets.zero),
        if (_pageToken != null)
          CloudPickerLoadMore(
            loading: _loading,
            onTap: () => _load(append: true),
          ),
        CloudPickerFoot(
          confirmLabel: _saving
              ? 'Saving…'
              : 'Sync $n folder${n == 1 ? '' : 's'}',
          onConfirm: canConfirm ? _confirm : null,
          onCancel: widget.onCancel,
          busy: _saving,
        ),
      ],
    );
  }
}
