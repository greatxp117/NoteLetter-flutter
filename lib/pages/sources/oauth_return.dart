import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cloud_file.dart';
import '../../models/cloud_integration.dart';
import '../../models/tag.dart';
import '../../shared/cloud_providers.dart';
import '../../shared/dates.dart';
import '../../state/cloud_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'cloud_sync_copy.dart';
import 'file_under.dart';
import 'folder_contents.dart' show cloudTypeLabel;
import 'import_review_queue.dart' show fmtFileSize;

/// The OAuth return (5.46.0, ADR-201; `screens/sources.md` §The OAuth return
/// — the prototype's `oauth` route, its D branch; web
/// `pages/sources/OAuthReturn.jsx`). It renders on `/sources` IN PLACE of the
/// Library while a return is open, for every provider (the prototype is
/// Notion's): the claim in flight, then either *{Provider}, Connected* — what
/// the provider offers in the column, the Manifest on the sheet — or one of
/// the notices. An app's `noteletter://cloud-connect` return is read exactly
/// like a `/sources` one ([SourcesPage] takes both).
///
/// Only measured figures (ADR-026/ADR-028): what the root listing answered and
/// what the reader ticked. No pages, passages or indexing time — the listing
/// knows none of them, and the prototype's are mock data. `partial` is not
/// knowable by anyone, so Notion gets standing guidance, never a finding.

/// The state's and the claim's lifetime (`api/cloud-storage.md`), which *The
/// Link Expired* says in words.
const returnTtlMinutes = 10;

const _cadence = {
  'hourly': 'every hour',
  'daily': 'once a day',
  'weekly': 'once a week',
};

/// Where a return stands (web SourcesBrowse's `ret.phase`).
enum ReturnPhase { claiming, claimed, refused, error }

/// A return the page is open on: the phase, the provider it is about (an
/// error redirect carries none — the one this client sent to consent is
/// remembered, `CloudReturn.recallConnecting`), the claim's answer, a
/// redirect's reason, or a refusal's sentence and reference.
class OAuthReturn {
  final ReturnPhase phase;
  final String? provider;
  final Map<String, dynamic>? answer;
  final String? reason;
  final String? refusal;
  final String? refusalRequestId;

  const OAuthReturn(
    this.phase, {
    this.provider,
    this.answer,
    this.reason,
    this.refusal,
    this.refusalRequestId,
  });
}

enum ReturnView { claiming, granted, empty, already, denied, expired, refused, failed }

/// The view a return opens on, from what the URL or the claim answered. Open
/// vocabulary: any `success` that is not `reconnected` is *Connected*, and any
/// reason this does not name is *Not Connected*.
ReturnView returnView(OAuthReturn r) {
  if (r.phase == ReturnPhase.claiming) return ReturnView.claiming;
  if (r.phase == ReturnPhase.refused) return ReturnView.refused;
  final a = r.answer;
  if (r.phase == ReturnPhase.claimed && a?['cloud_connect'] == 'success') {
    return a?['connection'] == 'reconnected'
        ? ReturnView.already
        : ReturnView.granted;
  }
  final reason = r.phase == ReturnPhase.claimed
      ? (a?['reason'] as String? ?? '')
      : (r.reason ?? '');
  if (reason == 'access_denied') return ReturnView.denied;
  if (reason == 'invalid_state') return ReturnView.expired;
  return ReturnView.failed;
}

/// A notice's words, provider-generic. [name] may be null (an error return
/// names no provider and this client did not start the connection).
typedef NoticeCopy = ({
  String title,
  String stand,
  String? log,
  String? body,
  String? primary,
  String secondary,
  bool toAdd,
});

NoticeCopy noticeCopy(
  ReturnView view, {
  String? name,
  String? reason,
  CloudIntegration? integration,
  String? provider,
}) {
  final n = name ?? 'the service';
  final notion = provider == 'notion';
  final folders = notion ? 'databases' : 'folders';
  final folder = notion ? 'database' : 'folder';
  switch (view) {
    case ReturnView.denied:
      return (
        title: 'Nothing Was Shared',
        stand: 'You declined access${name != null ? ' in the $name window' : ''}, '
            'so nothing came across. Your library is exactly as you left it.',
        log: 'error: ${reason == null || reason.isEmpty ? 'access_denied' : reason}',
        body: notion
            ? 'NoteLetter asks for read access to the pages you pick, and '
                'nothing else. If you’d rather not connect Notion, you can '
                'always drop files in by hand.'
            : 'NoteLetter asks $n for read access, and nothing else. If you’d '
                'rather not connect $n, you can always drop files in by hand.',
        primary: name != null ? 'Try $name again' : null,
        secondary: 'Add files instead',
        toAdd: true,
      );
    case ReturnView.expired:
      return (
        title: 'The Link Expired',
        stand: 'That authorisation sat open longer than ten minutes, so the '
            'link is no longer good. Nothing was connected.',
        log: 'error: invalid_state',
        body: 'This is a security measure, not a fault on your side. Starting '
            'again takes a few seconds.',
        primary: name != null ? 'Start again' : null,
        secondary: 'Back to library',
        toAdd: false,
      );
    case ReturnView.already:
      final k = integration?.folderIds.length ?? 0;
      return (
        title: 'Already Connected',
        stand: 'This $n account was connected already. Your sign-in was '
            'refreshed, and nothing else changed.',
        log: integration == null
            ? null
            : '${k > 0 ? kitCounted(k, 'sync $folder', 'sync $folders') : 'no sync $folders'}'
                ' · auto-sync ${integration.autoSyncEnabled ? 'on' : 'off'}',
        body: 'You can choose more of what $n offers, or change which $folders '
            'stay in sync from the Library.',
        primary: 'Choose what comes across',
        secondary: 'Back to library',
        toAdd: false,
      );
    case ReturnView.refused:
      return (
        title: 'Not Connected',
        stand: 'Nothing from $n was added to your library.',
        log: null,
        body: null,
        primary: name != null ? 'Connect $name again' : null,
        secondary: 'Back to library',
        toAdd: false,
      );
    case ReturnView.claiming:
    case ReturnView.granted:
    case ReturnView.empty:
    case ReturnView.failed:
      // failed: missing_params, connect_failed, any other provider error.
      return (
        title: 'Not Connected',
        stand: connectReasonCopy(provider, reason),
        log: 'error: ${reason == null || reason.isEmpty ? 'unknown' : reason}',
        body: 'Nothing was stored, and your library is exactly as you left it.',
        primary: name != null ? 'Try $name again' : null,
        secondary: 'Back to library',
        toAdd: false,
      );
  }
}

String _joinAnd(List<String> list) {
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

String _now() => kitClockTime(DateTime.now().millisecondsSinceEpoch);

/// One breakpoint (CLAUDE.md §Composition deviations): web stacks the offer
/// cards and the notice actions at 860.
bool _wide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= AppSpacing.compactWidth;

/// The page. [ret] is [SourcesPage]'s open return; [onLeave] shows the
/// Library again, with what *Bring in* queued (null for *Not now* and *Back
/// to library*); [onAddFiles] is *Add files instead*.
class OAuthReturnPage extends StatefulWidget {
  final OAuthReturn ret;
  final List<Tag> shelves;
  final ValueChanged<String?> onLeave;
  final VoidCallback onAddFiles;

  const OAuthReturnPage({
    super.key,
    required this.ret,
    required this.shelves,
    required this.onLeave,
    required this.onAddFiles,
  });

  @override
  State<OAuthReturnPage> createState() => _OAuthReturnPageState();
}

class _OAuthReturnPageState extends State<OAuthReturnPage> {
  late ReturnView _view = returnView(widget.ret);

  /// The time the page opened on this return — the folio's.
  String _at = _now();

  @override
  void didUpdateWidget(OAuthReturnPage old) {
    super.didUpdateWidget(old);
    if (old.ret != widget.ret) {
      _view = returnView(widget.ret);
      _at = _now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier>();
    final ret = widget.ret;
    final provider = (ret.answer?['provider'] as String?) ?? ret.provider;
    final name = cloudProviders[provider]?.name;
    final integration = provider == null ? null : cloud.integrationFor(provider);
    final email = integration?.providerEmail;
    final connectedFolio =
        'Connected · $_at${email != null && email.isNotEmpty ? ' · $email' : ''}';

    switch (_view) {
      case ReturnView.claiming:
        return KitDPage(
          folio: 'Returned from ${name ?? 'the service'} · $_at',
          title: 'Connecting ${name ?? 'Your Service'}',
          stand: 'Finishing the ${name ?? 'cloud'} connection…',
          child: Semantics(
            liveRegion: true,
            label: 'Finishing the ${name ?? 'cloud'} connection…',
            child: const KitSkeletonLines(
                lines: [KitSkelLine(0.6), KitSkelLine(0.4)]),
          ),
        );
      case ReturnView.granted when name != null:
        return _Manifest(
          key: ValueKey('manifest-$provider'),
          provider: provider!,
          name: name,
          integration: integration,
          shelves: widget.shelves,
          folio: connectedFolio,
          onLeave: widget.onLeave,
          onEmpty: () {
            if (mounted) setState(() => _view = ReturnView.empty);
          },
        );
      case ReturnView.empty:
        final notion = provider == 'notion';
        return KitDPage(
          folio: connectedFolio,
          title: 'Nothing to Bring In',
          stand: notion
              ? 'Notion is connected, but it shared no pages or databases '
                  'NoteLetter can list.'
              : '$name is connected, but it shared nothing NoteLetter can '
                  'list — no files or folders came across.',
          child: _NoticeColumn(
            body: notion
                ? 'Share a page with writing in it from the Notion permission '
                    'screen and connect again. The connection stays live in '
                    'the meantime.'
                : 'Add files to your $name, then browse it from the Library. '
                    'The connection stays live in the meantime.',
            log: '0 items listed',
            primary: notion ? 'Choose different pages' : null,
            onPrimary: notion ? _again(provider) : null,
            secondary: 'Back to library',
            // Without a way to connect again, *Back to library* is the one way
            // on, so it is the primary (web EmptyActions).
            secondaryPrimary: !notion,
            onSecondary: () => widget.onLeave(null),
          ),
        );
      default:
        final copy = noticeCopy(_view,
            name: name,
            reason: (ret.answer?['reason'] as String?) ?? ret.reason,
            integration: integration,
            provider: provider);
        return KitDPage(
          folio: _view == ReturnView.already
              ? connectedFolio
              : 'Returned from ${name ?? 'the service'} · $_at',
          title: copy.title,
          stand: copy.stand,
          child: _NoticeColumn(
            failure: _view == ReturnView.refused
                ? KitFailureBlock(
                    sentence: 'The connection was not finished.',
                    detail: ret.refusal ?? 'The request did not complete.',
                    requestId: ret.refusalRequestId,
                  )
                : null,
            body: copy.body,
            log: copy.log,
            primary: copy.primary,
            onPrimary: copy.primary == null
                ? null
                : _view == ReturnView.already
                    ? () async {
                        setState(() => _view = ReturnView.granted);
                        return null;
                      }
                    : _again(provider),
            secondary: copy.secondary,
            onSecondary: copy.toAdd ? widget.onAddFiles : () => widget.onLeave(null),
          ),
        );
    }
  }

  /// A primary that connects again goes through the one connect entry point
  /// (`CloudNotifier.connect`) and keeps its failure slot: the answer is the
  /// refusal's sentence, or null. An app's session that comes back is held and
  /// reaches [SourcesPage], which opens the page on the new return.
  Future<String?> Function()? _again(String? provider) => provider == null
      ? null
      : () => context.read<CloudNotifier>().connect(provider);
}

// ── The notices. Same masthead, single column, one way on. ──────────────────

/// What a notice says under its masthead: the failure block a refusal
/// carries, a serif body, a mono log line (only what was measured — the
/// reason the return carried), the actions (primary, then ghost; stacked
/// below the one breakpoint), and a connect-again's failure slot.
class _NoticeColumn extends StatefulWidget {
  final Widget? failure;
  final String? body;
  final String? log;
  final String? primary;

  /// Answers the failure slot's sentence, or null.
  final Future<String?> Function()? onPrimary;
  final String secondary;
  final bool secondaryPrimary;
  final VoidCallback onSecondary;

  const _NoticeColumn({
    this.failure,
    this.body,
    this.log,
    this.primary,
    this.onPrimary,
    required this.secondary,
    this.secondaryPrimary = false,
    required this.onSecondary,
  });

  @override
  State<_NoticeColumn> createState() => _NoticeColumnState();
}

class _NoticeColumnState extends State<_NoticeColumn> {
  bool _busy = false;
  String? _fail;

  Future<void> _primary() async {
    final run = widget.onPrimary;
    if (run == null) return;
    setState(() {
      _busy = true;
      _fail = null;
    });
    final err = await run();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _fail = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final bodyStyle = KitText.bodyReading(context, fontSize: 19, height: 30);
    final wide = _wide(context);
    final buttons = <Widget>[
      if (widget.primary != null)
        KitButton(
          _busy ? 'Connecting…' : widget.primary!,
          center: !wide,
          onPressed: _busy || widget.onPrimary == null ? null : _primary,
        ),
      KitButton(
        widget.secondary,
        variant: widget.secondaryPrimary
            ? KitButtonVariant.primary
            : KitButtonVariant.ghost,
        center: !wide,
        onPressed: widget.onSecondary,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.failure != null) ...[
          widget.failure!,
          const SizedBox(height: 22),
        ],
        if (widget.body != null)
          ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: 62 * KitText.ch(context, bodyStyle)),
            child: Text(widget.body!, style: bodyStyle),
          ),
        if (widget.log != null)
          Container(
            margin: const EdgeInsets.only(top: 22),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: AppRadius.smR,
            ),
            child: Text(widget.log!,
                style: KitText.monoMeta(context, letterSpacing: 0.06)),
          ),
        const SizedBox(height: 28),
        if (wide)
          Wrap(spacing: 10, runSpacing: 10, children: buttons)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                buttons[i],
              ],
            ],
          ),
        if (_fail != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: KitFailureInline(_fail!),
          ),
      ],
    );
  }
}

// ── {Provider}, Connected: what the provider is offering, and the Manifest ──

class _Manifest extends StatefulWidget {
  final String provider;
  final String name;
  final CloudIntegration? integration;
  final List<Tag> shelves;
  final String folio;
  final ValueChanged<String?> onLeave;
  final VoidCallback onEmpty;

  const _Manifest({
    super.key,
    required this.provider,
    required this.name,
    required this.integration,
    required this.shelves,
    required this.folio,
    required this.onLeave,
    required this.onEmpty,
  });

  @override
  State<_Manifest> createState() => _ManifestState();
}

class _ManifestState extends State<_Manifest> {
  /// Null: the listing has not answered.
  List<CloudFile>? _items;
  String? _pageToken;
  String? _listErr;
  bool _loading = false;

  /// Ticked ids, in the order ticked.
  final List<String> _picked = [];
  String? _shelf;
  bool _sync = true;
  bool _busy = false;
  String? _err;

  /// Only the latest listing may land (web `seq`).
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _fetch(null);
  }

  void _load([String? token]) {
    setState(() {
      _loading = true;
      _listErr = null;
    });
    _fetch(token);
  }

  Future<void> _fetch(String? token) async {
    final s = ++_seq;
    final res = await context
        .read<CloudNotifier>()
        .listOffer(widget.provider, pageToken: token);
    if (!mounted || s != _seq) return;
    final listing = res.listing;
    setState(() {
      _loading = false;
      if (listing == null) {
        _listErr = res.error;
        return;
      }
      final got = listing.items;
      _items = token != null && _items != null ? [..._items!, ...got] : got;
      _pageToken = listing.nextPageToken;
    });
    // A first page with nothing and no more to ask for: Nothing to Bring In.
    if (listing != null &&
        token == null &&
        listing.items.isEmpty &&
        listing.nextPageToken == null) {
      widget.onEmpty();
    }
  }

  List<CloudFile> get _rows => _items ?? const [];
  List<CloudFile> get _sel => [
        for (final id in _picked)
          for (final i in _rows)
            if (i.id == id) i,
      ];

  void _toggle(CloudFile item) {
    // The endpoint's caps (≤20 folders, ≤50 files): over them it refuses
    // rather than truncating, so the page refuses the tick instead.
    final folder = item.isFolder;
    final cap = folder ? kMaxImportFolders : kMaxImportFiles;
    final same = _sel.where((i) => i.isFolder == folder).length;
    setState(() {
      if (_picked.contains(item.id)) {
        _picked.remove(item.id);
      } else if (same < cap) {
        _picked.add(item.id);
      }
    });
  }

  /// The shelf chosen, while it is still in the library.
  String? get _filed =>
      shelfPathLabel(widget.shelves, _shelf) == null ? null : _shelf;

  Future<void> _bringIn() async {
    final sel = _sel;
    final folders = sel.where((i) => i.isFolder).toList();
    final files = sel.where((i) => !i.isFolder).toList();
    final shelf = _filed;
    final shelfLabel = shelfPathLabel(widget.shelves, shelf);
    setState(() {
      _busy = true;
      _err = null;
    });
    final res = await context.read<CloudNotifier>().bringIn(
          widget.provider,
          folderIds: [for (final f in folders) f.id],
          fileIds: [for (final f in files) f.id],
          folderNames: {
            for (final f in folders)
              if (f.name.isNotEmpty)
                f.id: f.name.length > 200 ? f.name.substring(0, 200) : f.name,
          },
          tagIds: shelf == null ? null : [shelf],
          // Keep in sync is the existing switch (ADR-201: no new sync model).
          keepInSync: _sync &&
              folders.isNotEmpty &&
              !(widget.integration?.autoSyncEnabled ?? false),
        );
    if (!mounted) return;
    if (res.error != null) {
      // §18: the failure slot is required — the server's sentence, verbatim.
      setState(() {
        _busy = false;
        _err = res.error;
      });
      return;
    }
    // ADR-103 §5: the figures are the ones the 202 COUNTED.
    final qf = res.folders;
    final qx = res.files;
    var note = 'Queued $qf folder${qf == 1 ? '' : 's'} and $qx '
        'file${qx == 1 ? '' : 's'} from ${widget.name}'
        '${shelfLabel != null ? ', filed under $shelfLabel' : ''}.';
    if (res.syncRefusal != null) {
      note += ' Keep in sync was not turned on — ${res.syncRefusal}';
    }
    widget.onLeave(note);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final notion = widget.provider == 'notion';
    final name = widget.name;
    final rows = _rows;
    final sel = _sel;
    final folderSel = sel.where((i) => i.isFolder).length;
    final fileSel = sel.length - folderSel;
    final nouns = notion
        ? const ['database', 'databases', 'page', 'pages']
        : const ['folder', 'folders', 'file', 'files'];
    final integration = widget.integration;
    final cadence = _cadence[integration?.syncFrequency] ?? 'on its schedule';
    final types = [
      for (final k in integration?.includeTypes ?? const <String>[])
        if (k.isNotEmpty) cloudTypeLabel(k),
    ];
    final shelfLabel = shelfPathLabel(widget.shelves, _filed);
    final n = sel.length;
    final fine = KitText.note(context, color: t.fgSubtle)
        .copyWith(height: 19 / 12.5);
    final wide = _wide(context);

    Widget guide(String text) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 62 * KitText.ch(context, fine)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: KitGlyph(Icons.visibility_outlined,
                    size: 14, color: t.fgSubtle),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(text, style: fine)),
            ],
          ),
        );

    final cards = [
      for (final i in rows)
        _OfferCard(
          item: i,
          notion: notion,
          refusal: cloudFileRefusal(widget.provider, i),
          on: _picked.contains(i.id),
          onToggle: () => _toggle(i),
        ),
    ];

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'What $name is offering',
          small: true,
          flushTop: true,
          meta: _items == null
              ? null
              : '${kitCounted(rows.length, 'item')}'
                  '${_pageToken != null ? ' so far' : ''}',
        ),
        if (notion)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: guide('Notion passes along only the pages you ticked on '
                'its permission screen — to bring more in, grant access in '
                'Notion and return.'),
          ),
        if (_listErr != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KitFailureInline(
                    'What $name offers could not be listed — $_listErr'),
                KitHxLink('Try again', onTap: _loading ? null : () => _load()),
              ],
            ),
          ),
        if (_items == null && _listErr == null)
          const KitSkeletonLines(lines: [
            KitSkelLine(),
            KitSkelLine(0.7),
            KitSkelLine(),
            KitSkelLine(0.6),
          ]),
        if (cards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _CardGrid(cards: cards, columns: wide ? 2 : 1),
          ),
        if (_pageToken != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: KitHxLink(_loading ? 'Loading…' : 'Load more',
                  onTap: _loading ? null : () => _load(_pageToken)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: guide('Read-only. NoteLetter reads the text of '
              '${notion ? 'these pages' : 'these files'} and never writes '
              'back to $name. Disconnect any time from the Library.'),
        ),
      ],
    );

    final syncOn = _sync && folderSel > 0;
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitDLabel('Manifest', first: true),
        KitFigures(top: 0, rows: [
          (folderSel == 1 ? nouns[0] : nouns[1], '$folderSel'),
          (fileSel == 1 ? nouns[2] : nouns[3], '$fileSel'),
        ]),
        const SizedBox(height: 18),
        FileUnder(
          shelves: widget.shelves,
          value: _filed,
          onChanged: (v) => setState(() => _shelf = v),
          disabled: _busy,
          note: 'Applies to what you bring in now.',
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KitSwitch(
              value: syncOn,
              tooltip: 'Keep in sync',
              // Held until a folder is ticked: only folders stay in sync.
              onChanged: folderSel == 0 || _busy
                  ? null
                  : (_) => setState(() => _sync = !_sync),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Keep in sync',
                      style: KitText.ui(context, weight: FontWeight.w500)
                          .copyWith(fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Text(
                    folderSel > 0
                        ? 'New files in ${folderSel == 1 ? 'this ${nouns[0]}' : 'these ${nouns[1]}'} '
                            'come in $cadence.'
                        : 'Only ${nouns[1]} stay in sync — tick one to keep it.',
                    style: KitText.small(context, color: t.fgSubtle, height: 17),
                  ),
                ],
              ),
            ),
          ],
        ),
        // What a folder brings in is the integration's include_types,
        // measured (an empty set imports nothing, 4.59.0). Notion's databases
        // bring in pages, so it has nothing to say there.
        if (folderSel > 0 && !notion && integration != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              types.isNotEmpty
                  ? 'From folders, NoteLetter takes these kinds: '
                      '${_joinAnd(types)}. Change which in Sync settings.'
                  : 'From folders, nothing is taken — no file type is ticked '
                      'in Sync settings.',
              style: KitText.small(context, color: t.fgSubtle, height: 17),
            ),
          ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.rule)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KitButton(
                _busy
                    ? 'Bringing in…'
                    : n > 0
                        ? 'Bring in ${kitCounted(n, 'item')}'
                        : 'Nothing selected',
                center: true,
                onPressed: n == 0 || _busy ? null : _bringIn,
              ),
              const SizedBox(height: 8),
              KitButton(
                'Not now',
                variant: KitButtonVariant.ghost,
                center: true,
                onPressed: _busy ? null : () => widget.onLeave(null),
              ),
            ],
          ),
        ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: KitFailureInline(_err!),
          ),
        const SizedBox(height: 18),
        Text(
          'Each document’s passages appear under Being catalogued as it is '
          'read. You can leave this page.',
          style: KitText.lede(context,
              fontSize: 12.5, height: 18, color: t.fgSubtle),
        ),
      ],
    );

    return KitDPage(
      folio: widget.folio,
      title: '$name, Connected',
      stand: 'Read-only access, granted. Choose what belongs in your library '
          '— nothing is copied until you say so.',
      sheet: KitDSheet(
        label: 'Manifest',
        peek: KitLibPeek(
          title: n > 0 ? '${kitCounted(n, 'item')} selected' : 'Nothing selected',
          meta: shelfLabel,
        ),
        body: card,
      ),
      child: main,
    );
  }
}

/// The offer's cards, two to a row (one below the breakpoint), 12 apart.
class _CardGrid extends StatelessWidget {
  final List<Widget> cards;
  final int columns;
  const _CardGrid({required this.cards, required this.columns});

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    for (var i = 0; i < cards.length; i += columns) {
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 12));
      lines.add(columns == 1
          ? cards[i]
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[i]),
                  const SizedBox(width: 12),
                  Expanded(
                      child: i + 1 < cards.length
                          ? cards[i + 1]
                          : const SizedBox.shrink()),
                ],
              ),
            ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: lines);
  }
}

/// One item the provider offers, as a card you tick — a slip of paper you
/// either keep or don't: the kind glyph (layers for a folder or database, a
/// page for a file), the name, and measured meta only. A file the upload
/// classifier refuses is drawn held, with the classifier's own sentence and no
/// checkbox.
class _OfferCard extends StatelessWidget {
  final CloudFile item;
  final bool notion;
  final String? refusal;
  final bool on;
  final VoidCallback onToggle;

  const _OfferCard({
    required this.item,
    required this.notion,
    required this.refusal,
    required this.on,
    required this.onToggle,
  });

  String _meta() {
    if (item.isFolder) {
      return notion ? 'Database' : 'Folder — and everything inside it';
    }
    final at = DateTime.tryParse(item.modifiedAt)?.toLocal();
    final bits = [
      fmtFileSize(item.size),
      cloudExportLabel(item) ?? '',
      if (at != null) 'updated ${dayDate(at)}',
    ].where((s) => s.isNotEmpty).join(' · ');
    return bits.isNotEmpty ? bits : (notion ? 'Page' : 'File');
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final off = refusal != null;
    final lit = on && !off;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        KitGlyph(
          item.isFolder ? Icons.layers_outlined : Icons.description_outlined,
          size: 16,
          color: lit ? t.accent : t.fgSubtle,
        ),
        const SizedBox(height: 12),
        Text(item.name,
            style: KitText.label(context, weight: FontWeight.w600)
                .copyWith(fontSize: 14.5)),
        const SizedBox(height: 3),
        Text(refusal ?? _meta(), style: KitText.note(context, color: t.fgSubtle)),
      ],
    );
    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 44, 15),
      decoration: BoxDecoration(
        color: lit ? t.accentChipBg : t.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: lit ? t.accent : t.border),
      ),
      child: body,
    );
    if (off) {
      return Opacity(opacity: AppSpacing.heldOpacity, child: card);
    }
    return Semantics(
      checked: on,
      label: 'Bring in ${item.name}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Stack(
          // The card takes the row's height beside a taller neighbour.
          fit: StackFit.passthrough,
          children: [
            card,
            Positioned(
              top: 14,
              right: 14,
              child: SizedBox(
                width: 20,
                height: 20,
                child: KitCheckbox(
                  value: on,
                  onChanged: onToggle,
                  semanticsLabel: 'Bring in ${item.name}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
