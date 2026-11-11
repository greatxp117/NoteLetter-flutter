import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/cloud_file.dart';
import '../../models/cloud_integration.dart';
import '../../services/api.dart' show ImportPartial, kImportFileBatch;
import '../../shared/cloud_providers.dart';
import '../../shared/cloud_return.dart';
import '../../shared/dates.dart';
import '../../state/cloud_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'cloud_sync_copy.dart';
import 'folder_contents.dart' show cloudTypeLabel;
import 'import_review_queue.dart' show fmtFileSize;

/// The OAuth return (5.46.0, ADR-201; 5.52.0, ADR-203; `screens/sources.md`
/// §The OAuth return — the prototype's `oauth` route, its D branch; web
/// `pages/ConnectReturn.jsx` + `pages/sources/OAuthReturn.jsx`): the connect
/// page, for every provider (the prototype is Notion's) — the claim in
/// flight, then either *{Provider}, Connected* — what the provider offers in
/// the column, the Manifest on the sheet — or one of the notices. Since 5.52.0
/// it is its own route, `/connect/:provider` ([ConnectPage]), which an app's
/// `noteletter://cloud-connect` return opens ([ConnectOnReturn]); until then it
/// drew in place of the Library on `/sources`.
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

/// Where a return stands (web ConnectReturn's `ret.phase`). `direct` is the
/// page reopened with nothing to answer, for a provider found connected
/// (5.52.0, ADR-203).
enum ReturnPhase { claiming, claimed, refused, error, direct }

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
  if (r.phase == ReturnPhase.direct) return ReturnView.granted;
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

/// How many listing pages one run of Notion's offer follows on its own
/// (5.56.0, ADR-208; web `NOTION_FOLLOW_PAGES`): 20 × 50 = 1,000 items. A
/// bound, so a pathological workspace or a cursor that never ends cannot list
/// forever; past it, Load more continues.
const int kNotionFollowPages = 20;

/// Notion's offer arrives ticked (5.52.0, ADR-203; web `tickOffer`): the
/// reader chose these pages on Notion's permission screen seconds ago, so
/// asking again is a second picker for one decision. A drive's root listing is
/// everything the reader owns — nothing they chose — so nothing is ticked
/// there (the caller asks only for Notion). Ticks [got] after [picked]: every
/// file, and folders up to the cap, counting what is already ticked by its
/// kind ([folderById], every row listed so far); an item the import would
/// refuse is never ticked. Returns a new list, in tick order.
List<String> tickOffer(List<String> picked, Iterable<CloudFile> got,
    Map<String, bool> folderById, String provider) {
  final n = [...picked];
  var folders = 0;
  for (final id in n) {
    if (folderById[id] == true) folders += 1;
  }
  for (final i in got) {
    if (n.contains(i.id) || cloudFileRefusal(provider, i) != null) continue;
    if (!i.isFolder) {
      n.add(i.id);
    } else if (folders < kMaxImportFolders) {
      n.add(i.id);
      folders += 1;
    }
  }
  return n;
}

/// The line under a ticked offer when the folder cap left listed folders
/// unticked (web `capLines`). Only when the cap is what stopped it: a reader
/// who unticked some has room, and is told nothing. Files have no line since
/// 5.56.0 — every one is ticked and Bring in sends them all.
List<String> capLines(
    List<CloudFile> rows, Iterable<String> picked, String provider) {
  final on = picked.toSet();
  final folders = rows
      .where((i) => i.isFolder && cloudFileRefusal(provider, i) == null)
      .toList();
  final nd = folders.where((i) => on.contains(i.id)).length;
  final many = provider == 'notion' ? 'databases' : 'folders';
  return [
    if (nd >= kMaxImportFolders && folders.length > nd)
      'The first $kMaxImportFolders $many are ticked — one import takes '
          '$kMaxImportFolders at a time. Bring these in, then choose the rest '
          'from the Library.',
  ];
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

/// The views. [ret] is [ConnectPage]'s return; [onLeave] goes to the
/// Library, with what *Bring in* queued (null for *Not now* and *Back to
/// library*); [onAddFiles] is *Add files instead*.
class OAuthReturnPage extends StatefulWidget {
  final OAuthReturn ret;
  final ValueChanged<String?> onLeave;
  final VoidCallback onAddFiles;

  const OAuthReturnPage({
    super.key,
    required this.ret,
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
  /// reaches the open [ConnectPage], which answers the new return in place.
  Future<String?> Function()? _again(String? provider) => provider == null
      ? null
      : () => context.read<CloudNotifier>().connect(provider);
}

// ── The route (5.52.0, ADR-203; web `pages/ConnectReturn.jsx`) ──────────────

/// The connect page: its own route, `/connect/:provider` (and `/connect`).
/// What it answers, in order:
/// * a return held for it ([CloudReturn.take]) — an app's
///   `noteletter://cloud-connect` session, or a web build's `/connect?…`
///   callback that the router held and stripped: an error result, or a claim
///   spent here, once. `org: "enabled"` and `insufficient_scope` are about
///   organization, not a connection, so they are handed to the Library;
/// * nothing — Back, a reload, a copied link. Then `/connect/{provider}` opens
///   *{Provider}, Connected* while that provider is connected and its sign-in
///   is live, and the Library otherwise; `/connect` alone is the Library. A
///   notice is never reopened: what it said came with the return.
///
/// Leaving (*Not now*, *Back to library*, *Bring in*) goes to `/sources`,
/// saying what it should say there through [ConnectHandoff].
class ConnectPage extends StatefulWidget {
  /// The route's provider id, or null on `/connect`.
  final String? provider;

  const ConnectPage({super.key, this.provider});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  OAuthReturn? _ret;

  /// The Library is asked for once.
  bool _left = false;

  @override
  void initState() {
    super.initState();
    // Taken now, before anything draws: a claim is spent by its first request,
    // so nothing else may find it.
    final r = CloudReturn.take();
    CloudReturn.pending.addListener(_onHeld);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (r != null && (r.result == 'error' || r.result == 'claim')) {
        unawaited(_act(r));
      } else {
        unawaited(_direct());
      }
    });
  }

  @override
  void dispose() {
    CloudReturn.pending.removeListener(_onHeld);
    super.dispose();
  }

  /// A return that arrives while the page is open — a notice's *Try again* —
  /// is answered here, in place.
  void _onHeld() {
    if (!mounted || CloudReturn.pending.value == null) return;
    final r = CloudReturn.take();
    if (r != null) unawaited(_act(r));
  }

  /// The address names the provider as soon as anything does: `/connect`
  /// becomes `/connect/{provider}` in place — no history step that forwards.
  /// Only a PUSHED page is renamed: go_router's replace keeps a pushed page
  /// and its state, but over a page reached by address it is a `go`, which
  /// would build a new page and drop the answer on screen. A page reached by
  /// address keeps the one it was given: `router.dart`'s `holdConnectReturn`
  /// has already named whatever the params or this run remember (a web
  /// build's fresh load, which recalls the provider from storage, stays on
  /// `/connect`; its page still names it).
  void _name(String? provider) {
    if (!mounted || provider == null) return;
    if (!cloudProviders.containsKey(provider) || provider == widget.provider) {
      return;
    }
    final router = GoRouter.of(context);
    final at = router.routerDelegate.currentConfiguration.matches;
    if (at.isEmpty || at.last is! ImperativeRouteMatch) return;
    router.replace(CloudReturn.location(provider));
  }

  /// Leave for the Library, saying what it should say there.
  void _toLibrary({
    String? note,
    String? orgEnabled,
    ({String? provider, String reason})? connectError,
  }) {
    ConnectHandoff.handOff(
        note: note, orgEnabled: orgEnabled, connectError: connectError);
    if (_left || !mounted) return;
    _left = true;
    GoRouter.of(context).go('/sources');
  }

  // The OAuth return (ADR-012, ADR-158, ADR-159; api/cloud-storage.md §Client
  // behavior on return). We do NOT infer a connection from the URL or from an
  // integrations diff: the claim's answer is the source of truth.
  Future<void> _act(CloudReturn r) async {
    if (r.result == 'error') {
      // An error return names no provider (api/cloud-storage.md §Result
      // params): the one this client sent to consent is remembered.
      final provider = r.provider ?? await CloudReturn.recallConnecting();
      if (!mounted) return;
      final reason = r.reason ?? '';
      if (reason == 'insufficient_scope') {
        _toLibrary(connectError: (provider: provider, reason: reason));
        return;
      }
      setState(() => _ret =
          OAuthReturn(ReturnPhase.error, provider: provider, reason: reason));
      _name(provider);
      return;
    }
    // `error` and `claim` are the only results a return carries (5.0.0);
    // anything else is believed by nobody.
    final claim = r.claim;
    if (r.result != 'claim' || claim == null || claim.isEmpty) return;
    final cloud = context.read<CloudNotifier>();
    setState(() => _ret = OAuthReturn(ReturnPhase.claiming, provider: r.provider));
    _name(r.provider);
    final (:answer, :refusal, :requestId) = await cloud.claim(claim);
    if (!mounted) return;
    final res = answer;
    if (res == null) {
      if (refusal == null) {
        // None at all: the session ended, and sign-in has the screen.
        _toLibrary();
        return;
      }
      // A refusal (403 another account started it, 404 expired or already
      // finished) — its own sentence, verbatim (§14), on this page.
      setState(() => _ret = OAuthReturn(ReturnPhase.refused,
          provider: r.provider,
          refusal: refusal,
          refusalRequestId: requestId));
      return;
    }
    final provider = (res['provider'] as String?) ?? r.provider;
    if (res['cloud_connect'] == 'success' && res['org'] == 'enabled') {
      // org_upgrade: confirm the write-scope grant on the Library — the
      // reader was not importing, so no page here.
      _toLibrary(orgEnabled: provider ?? '');
    } else if (res['cloud_connect'] != 'success' &&
        res['reason'] == 'insufficient_scope') {
      _toLibrary(
          connectError: (provider: provider, reason: 'insufficient_scope'));
    } else {
      setState(() => _ret =
          OAuthReturn(ReturnPhase.claimed, provider: provider, answer: res));
      _name(provider);
    }
  }

  /// Nothing to answer: the page stands only for a provider that is connected
  /// and whose sign-in is live — not connected, an unknown id, or integrations
  /// that could not be read are the Library.
  Future<void> _direct() async {
    final p = widget.provider;
    if (p == null || !cloudProviders.containsKey(p)) {
      _toLibrary();
      return;
    }
    final cloud = context.read<CloudNotifier>();
    await cloud.loadIntegrations();
    if (!mounted || _ret != null) return;
    final i = cloud.integrationsError != null ? null : cloud.integrationFor(p);
    if (i == null || i.needsReconnect) {
      _toLibrary();
      return;
    }
    setState(() => _ret = OAuthReturn(ReturnPhase.direct, provider: p));
  }

  @override
  Widget build(BuildContext context) {
    final ret = _ret;
    if (ret == null) {
      return const KitPage(
        child: KitSkeletonLines(
            lines: [KitSkelLine(0.6), KitSkelLine(0.4)], top: 0),
      );
    }
    return OAuthReturnPage(
      ret: ret,
      onLeave: (note) => _toLibrary(note: note),
      onAddFiles: () {
        _left = true;
        GoRouter.of(context).go('/sources/add');
      },
    );
  }
}

/// The app's return opens the connect page as its own route (5.52.0,
/// ADR-203): when an auth session hands back `noteletter://cloud-connect` —
/// from Sources, quick add, Settings, wherever the reader pressed Connect —
/// the app goes to Sources and pushes `/connect/{provider}` over it, so Back
/// leaves the page for Sources. An open connect page answers a return itself
/// ([ConnectPage]); the push waits a frame, so a page that takes the return
/// first leaves nothing to open. Mounted once, around the app shell's pages
/// (`router.dart`); a return held while it was not mounted (the reader is
/// outside the shell) is opened when it mounts.
class ConnectOnReturn extends StatefulWidget {
  final Widget child;
  const ConnectOnReturn({super.key, required this.child});

  @override
  State<ConnectOnReturn> createState() => _ConnectOnReturnState();
}

class _ConnectOnReturnState extends State<ConnectOnReturn> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    CloudReturn.pending.addListener(_onHeld);
    _onHeld();
  }

  @override
  void dispose() {
    CloudReturn.pending.removeListener(_onHeld);
    super.dispose();
  }

  void _onHeld() {
    if (CloudReturn.pending.value == null || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _open();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _open() {
    final r = CloudReturn.pending.value;
    if (!mounted || r == null) return;
    final router = GoRouter.of(context);
    // The TOP page's address — a pushed page's own, not the one under it.
    final String here;
    try {
      here = router.state.uri.path;
    } catch (_) {
      return; // no configuration yet; the next return will find one
    }
    // An open connect page takes it itself.
    if (CloudReturn.isConnectPath(here)) return;
    if (here != '/sources') router.go('/sources');
    // An error return names no provider; the one this run sent to consent
    // does (the session fills it in, `CloudReturn.runSession`).
    unawaited(router.push(
        CloudReturn.location(r.provider ?? CloudReturn.connectingProvider)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
          busy: _busy,
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
  final String folio;
  final ValueChanged<String?> onLeave;
  final VoidCallback onEmpty;

  const _Manifest({
    super.key,
    required this.provider,
    required this.name,
    required this.integration,
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
  bool _sync = true;
  bool _busy = false;
  String? _err;

  /// Files the 202s have accepted while a batched Bring in runs (measured);
  /// null when it is one request.
  int? _sent;

  /// What refused batches already queued (5.56.0): Bring in again sends the
  /// rest, and the Library's notice says the sums, as one import.
  int _queuedFolders = 0;
  int _queuedFiles = 0;

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

  /// One run of the listing from [token]. Notion's runs follow the listing's
  /// own `nextPageToken`, up to [kNotionFollowPages] pages (5.56.0, ADR-208):
  /// its offer is the reader's selection, and one shown 50 at a time behind
  /// Load more was the cap under another name. A drive's listing is one page
  /// a run. [_loading] stays true for the whole run — it is what holds Bring
  /// in while Notion's offer is still arriving.
  Future<void> _fetch(String? token) async {
    final s = ++_seq;
    final notion = widget.provider == 'notion';
    var next = token;
    var pages = 0;
    while (true) {
      final res = await context
          .read<CloudNotifier>()
          .listOffer(widget.provider, pageToken: next);
      if (!mounted || s != _seq) return;
      final listing = res.listing;
      if (listing == null) {
        // A later page that failed keeps the token it was asked with, so Try
        // again and Load more continue from it.
        setState(() {
          _loading = false;
          _listErr = res.error;
        });
        return;
      }
      final fresh = next == null;
      setState(() {
        final got = listing.items;
        _items = !fresh && _items != null ? [..._items!, ...got] : got;
        _pageToken = listing.nextPageToken;
        // Notion's offer arrives ticked, page by page (5.52.0, ADR-203); a
        // first page starts the ticks afresh.
        if (notion) {
          final ticked = tickOffer(fresh ? const [] : _picked, got,
              {for (final i in _items!) i.id: i.isFolder}, widget.provider);
          _picked
            ..clear()
            ..addAll(ticked);
        }
      });
      // A first page with nothing and no more to ask for: Nothing to Bring In.
      if (fresh && listing.items.isEmpty && listing.nextPageToken == null) {
        setState(() => _loading = false);
        widget.onEmpty();
        return;
      }
      next = listing.nextPageToken;
      pages += 1;
      if (!(notion && next != null && pages < kNotionFollowPages)) break;
    }
    setState(() => _loading = false);
  }

  List<CloudFile> get _rows => _items ?? const [];
  List<CloudFile> get _sel => [
        for (final id in _picked)
          for (final i in _rows)
            if (i.id == id) i,
      ];

  void _toggle(CloudFile item) {
    // The endpoint's folder cap (≤20): over it it refuses rather than
    // truncating, so the page refuses the tick instead. Files are uncapped —
    // Bring in sends them in batches (5.56.0, ADR-208).
    final folder = item.isFolder;
    final folders = _sel.where((i) => i.isFolder).length;
    setState(() {
      if (_picked.contains(item.id)) {
        _picked.remove(item.id);
      } else if (!folder || folders < kMaxImportFolders) {
        _picked.add(item.id);
      }
    });
  }

  /// The Library's notice for everything queued — this press's 202s plus any
  /// a refused batch queued before it (web `leave`).
  void _leave(int qf, int qx, [String extra = '']) {
    final f = _queuedFolders + qf;
    final x = _queuedFiles + qx;
    widget.onLeave('Queued $f folder${f == 1 ? '' : 's'} and $x '
        'file${x == 1 ? '' : 's'} from ${widget.name}.$extra');
  }

  /// Not now after a refused batch still says what was queued.
  void _notNow() {
    if (_queuedFolders > 0 || _queuedFiles > 0) {
      _leave(0, 0);
    } else {
      widget.onLeave(null);
    }
  }

  Future<void> _bringIn() async {
    final sel = _sel;
    final folders = sel.where((i) => i.isFolder).toList();
    final files = sel.where((i) => !i.isFolder).toList();
    final fileIds = [for (final f in files) f.id];
    setState(() {
      _busy = true;
      _err = null;
      _sent = fileIds.length > kImportFileBatch ? 0 : null;
    });
    final res = await context.read<CloudNotifier>().bringIn(
          widget.provider,
          folderIds: [for (final f in folders) f.id],
          // More than 50 files go 50 to a request, the folders in the first
          // (5.56.0, ADR-208; Api.importFromCloud).
          fileIds: fileIds,
          folderNames: {
            for (final f in folders)
              if (f.name.isNotEmpty)
                f.id: f.name.length > 200 ? f.name.substring(0, 200) : f.name,
          },
          // No File under (5.52.0, ADR-203): what comes in is shelved by
          // indexing, as every document is (INV-12) — `tag_ids` is never sent.
          // Keep in sync is the existing switch (ADR-201: no new sync model).
          keepInSync: _sync &&
              folders.isNotEmpty &&
              !(widget.integration?.autoSyncEnabled ?? false),
          onProgress: (sent, _) {
            if (mounted) setState(() => _sent = sent);
          },
        );
    if (!mounted) return;
    if (res.error != null) {
      // §18: the failure slot is required — the server's sentence, verbatim.
      final ImportPartial? partial = res.partial;
      setState(() {
        _busy = false;
        _sent = null;
        if (partial != null) {
          // What the earlier batches queued IS queued: kept for the Library's
          // notice, unticked here; the unsent stay ticked so Bring in sends
          // them.
          _queuedFolders += partial.queuedFolders;
          _queuedFiles += partial.queuedFiles;
          _picked
            ..clear()
            ..addAll(partial.unsent);
          _err = partialImportSentence(partial, fileIds.length, res.error!,
                  noun: widget.provider == 'notion' ? 'pages' : 'files',
                  folderNoun: widget.provider == 'notion' ? 'database' : 'folder') +
              (res.syncRefusal != null
                  ? ' Keep in sync was not turned on — ${res.syncRefusal}'
                  : '');
        } else {
          _err = res.error;
        }
      });
      return;
    }
    // ADR-103 §5: the figures are the ones the 202 COUNTED.
    _leave(
        res.folders,
        res.files,
        res.syncRefusal != null
            ? ' Keep in sync was not turned on — ${res.syncRefusal}'
            : '');
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
    final capped = notion ? capLines(rows, _picked, widget.provider) : const <String>[];
    // Notion's offer is still being listed (5.56.0): Bring in is held, so a
    // press cannot leave the rest of what the reader shared behind.
    final following = notion && _loading;
    final n = sel.length;
    final fine = KitText.note(context, color: t.fgSubtle)
        .copyWith(height: 19 / 12.5);
    final wide = _wide(context);

    // `.or-guide` / `.or-fine`: the eye, then the line; the cap line is the
    // same face with no eye.
    Widget guide(String text, {bool eye = true}) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 62 * KitText.ch(context, fine)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eye) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: KitGlyph(Icons.visibility_outlined,
                      size: 14, color: t.fgSubtle),
                ),
                const SizedBox(width: 9),
              ],
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
                // A later page that failed keeps its token: Try again
                // continues from it, and keeps what the reader unticked.
                KitHxLink('Try again',
                    busy: _loading,
                    onTap: _loading
                        ? null
                        : () => _load(
                            (_items?.isNotEmpty ?? false) ? _pageToken : null)),
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
        // When a cap left listed items unticked, it says so under the offer
        // (5.52.0, ADR-203; web `.or-guide`, 0 above and 16 below).
        for (final line in capped)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: guide(line, eye: false),
          ),
        if (_pageToken != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: KitHxLink(_loading ? 'Loading…' : 'Load more',
                    busy: _loading,
                  onTap: _loading ? null : () => _load(_pageToken)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: guide('Read-only. NoteLetter reads the text of '
              '${notion ? 'these pages' : 'these files'} and never writes '
              'back to $name. Disconnect any time under Manage in the Library.'),
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
        // No File under (5.52.0, ADR-203): the tally, then Keep in sync.
        const SizedBox(height: 18),
        KitSyncSwitch(
          value: syncOn,
          label: 'Keep in sync',
          sub: folderSel > 0
              ? 'New files in ${folderSel == 1 ? 'this ${nouns[0]}' : 'these ${nouns[1]}'} '
                  'come in $cadence.'
              : 'Only ${nouns[1]} stay in sync — tick one to keep it.',
          // Held until a folder is ticked: only folders stay in sync.
          onChanged: folderSel == 0 || _busy
              ? null
              : (_) => setState(() => _sync = !_sync),
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
                    ? (_sent != null
                        ? 'Bringing in… $_sent of $fileSel '
                            '${notion ? 'pages' : 'files'}'
                        : 'Bringing in…')
                    : following
                        ? 'Listing what Notion shared…'
                        : n > 0
                            ? 'Bring in ${kitCounted(n, 'item')}'
                            : 'Nothing selected',
              center: true,
              busy: _busy,
              onPressed: n == 0 || _busy || following ? null : _bringIn,
              ),
              const SizedBox(height: 8),
              KitButton(
                'Not now',
                variant: KitButtonVariant.ghost,
                center: true,
                onPressed: _busy ? null : _notNow,
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
        Text(item.name, style: KitText.offerName(context)),
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
