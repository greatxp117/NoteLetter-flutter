import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../models/ask_thread.dart';
import '../shared/source_host.dart';
import '../state/tags_notifier.dart';
import '../state/chat_notifier.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';

/// Ask — conversational retrieval over the reader's own notes, with the
/// conversations kept (contract 4.53.0/4.54.0, ADR-090; `spec/screens/ask.md`).
///
/// Composition (ADR-041): a bespoke head block (§2, with an eyebrow) over a
/// two-column body — the **Inspector rail** (§9) holding conversation history,
/// and the thread beside it — closed by a **composer dock** (§10). The empty
/// state is §7, a failed turn is §14.2 in the dock, a failed subscription is
/// §14.1 where the content would have been, and a citation's excerpt renders
/// its extraction markers inline (§17.2).
///
/// On a phone — which is every device this client ships to — §9's rail is an
/// **overlay with a backdrop and a visible close control**, reached from the
/// header's one action. The grouping, the labels and the active marker are
/// unchanged; that is the pattern's own phone form, not an adaptation.
///
/// Retrieval-only: there is no composed prose answer, so a library message is
/// its citations. The previous version of this screen built a paragraph out of
/// the top chunk's text and showed it as the app's own sentence.
class ChatPage extends StatefulWidget {
  /// The OPEN conversation, from `/ask/thread/{threadId}` (4.65.0, ADR-101).
  /// Null is the new-conversation state.
  final String? threadId;

  /// The shelf this screen is asking, from `/ask/shelf/{tagId}` (4.62.0,
  /// ADR-098). An open thread's own scope wins over it.
  final String? scopeTagId;

  const ChatPage({super.key, this.threadId, this.scopeTagId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

/// The prompts the empty state offers. Copy the reference's, verbatim.
const _prompts = <String>[
  'What have I been reading about lately?',
  'Summarize my notes on systems thinking',
  'What are the recurring ideas across my library?',
  'Find passages about attention and focus',
];

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _railOpen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // The screen follows the ROUTE, and does so before the first frame: a
    // cold open of `/ask/thread/{id}` must subscribe to that transcript, not
    // render the new-conversation state and then correct itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRoute());
  }

  @override
  void didUpdateWidget(covariant ChatPage old) {
    super.didUpdateWidget(old);
    if (old.threadId != widget.threadId || old.scopeTagId != widget.scopeTagId) {
      _syncRoute();
    }
  }

  void _syncRoute() {
    if (!mounted) return;
    context.read<ChatNotifier>().syncRoute(
          threadId: widget.threadId,
          tagId: widget.scopeTagId,
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final notifier = context.read<ChatNotifier>();
    // The box clears at SEND, because the question is now in the transcript
    // (ADR-097). It is not lost: a refusal leaves the turn on screen with the
    // server's sentence and a retry, and a question returned to the composer
    // would be the screen saying it had never been asked.
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    _controller.clear();
    _scrollToEnd();
    final threadId = await notifier.ask(question);
    if (!mounted) return;
    // The first turn MOVES to the thread the endpoint recorded — after it is
    // recorded, never before (ADR-022, ADR-101).
    if (threadId != null) context.go('/ask/thread/$threadId');
    _scrollToEnd();
  }

  /// Re-send the turn that is on screen. It is not a draft — putting it back
  /// in the composer would be the screen saying it was never asked (ADR-097).
  Future<void> _retry() async {
    final threadId = await context.read<ChatNotifier>().retry();
    if (!mounted) return;
    if (threadId != null) context.go('/ask/thread/$threadId');
    _scrollToEnd();
  }

  /// The address this screen is AT — one of ADR-101's three forms. A citation
  /// hands it to the Reader as `?from=`, so the Reader's back control can name
  /// this conversation and return to it.
  String _routePath() {
    if (widget.threadId != null) return '/ask/thread/${widget.threadId}';
    if (widget.scopeTagId != null) return '/ask/shelf/${widget.scopeTagId}';
    return '/ask';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// The shelf's name for this screen's copy. The open thread's own stored
  /// title first (it is what the conversation was ASKED with), then the live
  /// shelf the route named, then a word — a scoped turn whose shelf title is
  /// not known yet is still scoped, and dropping the scope from the copy would
  /// be the screen claiming it searched the library (ADR-098).
  String? _scopeName(ChatNotifier ask) {
    String? routeTitle;
    final id = widget.scopeTagId;
    if (id != null) {
      for (final tag in context.read<TagsNotifier>().tags) {
        if (tag.id == id) routeTitle = tag.title;
      }
    }
    return ask.scopeName(routeTitle);
  }

  @override
  Widget build(BuildContext context) {
    final ask = context.watch<ChatNotifier>();
    final t = Tokens.of(context);
    final scope = _scopeName(ask);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.frameGutterCompact,
                  AppSpacing.s6, AppSpacing.frameGutterCompact, 0),
              // Scoped, the header NAMES the shelf — all three lines of it.
              // A screen that searches one shelf while reading like the
              // library is the control lying a second time (ADR-098).
              child: ScreenHeader(
                eyebrow: scope == null
                    ? 'Grounded in your library'
                    : 'Grounded in one shelf',
                title: scope == null ? 'Ask your library' : 'Ask $scope',
                standfirst: scope == null
                    ? 'Find what you’ve read on a topic — every result traces '
                        'back to a passage.'
                    : 'Only passages on this shelf are searched — every result '
                        'traces back to one.',
                action: KitButton.ghost(
                  'History',
                  icon: Icons.history,
                  onPressed: () => setState(() => _railOpen = true),
                ),
              ),
            ),
            Expanded(child: _thread(context, ask)),
          ],
        ),
        // The dock floats over the transcript, as §10 requires.
        Align(
          alignment: Alignment.bottomCenter,
          child: KitComposerDock(
            controller: _controller,
            placeholder:
                scope == null ? 'Ask your library anything…' : 'Ask $scope anything…',
            busy: ask.sending,
            // No `error` here any more (ADR-097). The refusal belongs to the
            // TURN, which is on screen above this dock with the question it
            // refused — beside a composer the reader has already emptied, the
            // same sentence would be about nothing.
            maxLength: 1000,
            onSend:
                _controller.text.trim().isEmpty || ask.sending ? null : _send,
          ),
        ),
        // §9's phone form: a backdrop that closes on press, then the rail.
        if (_railOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _railOpen = false),
              child: ColoredBox(color: t.scrim),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _rail(context, ask),
          ),
        ],
      ],
    );
  }

  Widget _rail(BuildContext context, ChatNotifier ask) {
    final width = MediaQuery.sizeOf(context).width;
    return KitInspectorRail(
      title: 'Conversations',
      width: width * 0.86 > 320 ? 320 : width * 0.86,
      onClose: () => setState(() => _railOpen = false),
      newLabel: 'New conversation',
      newActive: ask.activeId == null,
      // "New conversation" LEAVES the scope and the open thread — one
      // navigation covers both, because both are `/ask` (ADR-098, ADR-101). A
      // control that stayed scoped would offer the whole library while asking
      // a shelf.
      onNew: () {
        setState(() => _railOpen = false);
        context.go('/ask');
      },
      notice: ask.railError != null
          ? KitFailureBlock(
              sentence: 'Your conversations could not be read.',
              detail: ask.railError!,
            )
          : (ask.loadingThreads
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  child: Text('Loading…', style: KitText.meta(context)),
                )
              : null),
      groups: _groups(context, ask),
    );
  }

  List<KitRailGroup> _groups(BuildContext context, ChatNotifier ask) {
    final out = <KitRailGroup>[];
    for (final thread in ask.threads) {
      final label = _groupOf(thread.updatedAt);
      final name = thread.title.isEmpty ? 'Untitled' : thread.title;
      final entry = KitRailEntry(
        title: name,
        // §9.2 — nothing at all when the conversation is unscoped.
        scope: thread.tagId == null
            ? null
            : (thread.tagTitle?.isNotEmpty == true ? thread.tagTitle : 'shelf'),
        time: _entryTime(thread.updatedAt),
        preview: thread.preview,
        active: thread.id == ask.activeId,
        // Opening a conversation is a NAVIGATION (ADR-101): the thread is
        // `/ask/thread/{id}`, so a reload and every return from the Reader
        // land back in this transcript instead of on an empty screen.
        onTap: () {
          setState(() => _railOpen = false);
          // Only when it is a DIFFERENT conversation. `go` to the address the
          // screen is already at rebuilds the page — a new State, a new rail,
          // a new entry — and anything the reader had open in it (a rename
          // field, mid-edit) is torn down and committed empty by the teardown.
          // Re-opening the open conversation is not a navigation.
          if (thread.id != widget.threadId) {
            context.go('/ask/thread/${thread.id}');
          }
          _scrollToEnd();
        },
        // §9.1 (4.55.0, ADR-091) — the client surface `fn_ask_threads` PATCH
        // and DELETE had on no client until 4.55.0. The actions are SIBLINGS of
        // the tap that opens the entry, which is what the kit widget composes;
        // this file only says which two there are.
        actions: [
          KitRailEntryAction(
            icon: Icons.edit_outlined,
            label: 'Rename “$name”',
            onPressed: () => context.read<ChatNotifier>().startRename(thread.id),
          ),
          KitRailEntryAction(
            icon: Icons.delete_outline,
            label: 'Delete “$name”',
            danger: true,
            onPressed: () => _confirmDelete(thread.id, name),
          ),
        ],
        renaming: ask.renamingId == thread.id,
        busy: ask.entryBusy(thread.id),
        error: ask.entryError(thread.id),
        onRenameCommit: (v) =>
            context.read<ChatNotifier>().renameThread(thread.id, v),
        onRenameCancel: () => context.read<ChatNotifier>().cancelRename(),
      );
      if (out.isNotEmpty && out.last.label == label) {
        out.last.entries.add(entry);
      } else {
        out.add(KitRailGroup(label: label, entries: [entry]));
      }
    }
    return out;
  }

  /// §9.1: a destructive entry action confirms, and the confirmation names what
  /// is lost AND what is not. A conversation CITES passages; it does not hold
  /// them, so deleting one takes nothing out of the library.
  /// §18 (4.56.0, ADR-092): the delete runs inside the panel and its rejection
  /// renders there. §9.1's "the rejection goes in the entry" holds for the
  /// rename, which has no dialog — here the reader is looking at the
  /// confirmation, not at the row behind it.
  Future<void> _confirmDelete(String id, String name) async {
    final ask = context.read<ChatNotifier>();
    final wasOpen = id == widget.threadId;
    final deleted = await KitConfirm.show(
      context,
      title: 'Delete “$name”?',
      body: 'The questions in this conversation and the passages it found are '
          'removed. Nothing leaves your library — a conversation cites your '
          'passages, it does not hold them.',
      confirmLabel: 'Delete conversation',
      cancelLabel: 'Keep it',
      onConfirm: () => ask.deleteThread(id),
    );
    // A transcript whose thread is gone is a view of nothing, and the address
    // bar would be naming a conversation that no longer exists (ADR-101).
    //
    // The signal is §18's own: `KitConfirm` reports true only on SUCCESS, and
    // stays open answering on a refusal. Reading the rail instead — "has the
    // deleted thread left `threads` yet?" — is a race against the
    // subscription, and it lost: the delete had succeeded and the screen was
    // still on the dead thread's address.
    if (!mounted || !wasOpen || deleted != true) return;
    context.go('/ask');
  }

  Widget _thread(BuildContext context, ChatNotifier ask) {
    // A thread we could not READ is not an empty conversation (INV-24).
    if (ask.threadError != null) {
      return KitPage(
        width: KitFrameWidth.reading,
        child: KitFailureBlock(
          sentence: 'This conversation could not be read.',
          detail: ask.threadError!,
        ),
      );
    }

    final scope = _scopeName(ask);

    // §7 — an offer, not an apology. It stands only when nothing is open AND
    // nothing has been sent; a question already sent belongs in the
    // transcript, not behind a suggestion stack.
    if (ask.messages.isEmpty && ask.sentQuestion == null) {
      return KitPage(
        width: KitFrameWidth.reading,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s8),
          child: KitEmptyState(
            icon: Icons.auto_awesome,
            title: scope == null
                ? 'Ask your library a question'
                : 'Ask $scope a question',
            standfirst: scope == null
                ? 'Type a topic or question and NoteLetter will surface the '
                    'passages that relate to it.'
                : 'Type a topic or question and NoteLetter will surface the '
                    'passages on $scope that relate to it.',
            // The suggested prompts are about a WHOLE library, so a scoped
            // screen draws none: they would be a list of things this shelf
            // cannot answer (ADR-098).
            suggestions: [
              for (final p in scope == null ? _prompts : const <String>[])
                KitSuggestion(
                  icon: Icons.auto_awesome,
                  label: p,
                  onTap: () {
                    _controller.text = p;
                    _controller.selection = TextSelection.collapsed(
                        offset: _controller.text.length);
                  },
                ),
            ],
          ),
        ),
      );
    }

    return KitPage(
      width: KitFrameWidth.reading,
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in ask.messages)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: _AskMessageRow(message: m, from: _routePath()),
            ),
          // The turn the reader SENT (ADR-097). It is here from the moment it
          // goes until its own stored message arrives to replace it — and a
          // refusal leaves it here too, with the server's sentence and a
          // retry that re-sends THIS turn. Restoring a stored conversation
          // never draws it: it is only ever set by a request this screen made.
          if (ask.sentQuestion != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: _AskMessageRow(
                message: AskMessage(
                  id: '_sent',
                  role: AskRole.user,
                  text: ask.sentQuestion,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: _AskMessageRow(
                message: const AskMessage(id: '_answer', role: AskRole.library),
                searching: ask.sentError == null,
                failure: ask.sentError,
                onRetry: () => _retry(),
              ),
            ),
          ],
          // Room for the dock, which floats over this scroller.
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }
}

/// One message: a 36px circular avatar (sage for the reader, `--chrome` for the
/// app) beside a sans 12/600 attribution and the body.
class _AskMessageRow extends StatelessWidget {
  final AskMessage message;
  final bool searching;

  /// The server's sentence for a turn that was REFUSED (§14.2), rendered where
  /// the answer would have been — the question stays above it.
  final String? failure;
  final VoidCallback? onRetry;

  /// This conversation's own route, for a citation to carry onto the Reader.
  final String? from;

  const _AskMessageRow({
    required this.message,
    this.searching = false,
    this.failure,
    this.onRetry,
    this.from,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final mine = message.role == AskRole.user;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mine ? t.toneSage : t.chrome,
            shape: BoxShape.circle,
          ),
          child: mine
              ? Text(
                  'Y',
                  style: KitText.small(context, color: t.chromeFg, weight: FontWeight.w600),
                )
              : Icon(Icons.auto_awesome, size: 18, color: t.chromeFg),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mine ? 'You' : 'Your library',
                style: KitText.small(context, color: t.fgMuted, weight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.s1),
              if (failure != null) ...[
                KitFailureInline(failure!, dense: true),
                const SizedBox(height: AppSpacing.s3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: KitButton.primary('Try again', onPressed: onRetry),
                ),
              ] else if (searching)
                Text('Searching…', style: KitText.meta(context))
              // The reader's text is UI sans 15/22; the app's side is its
              // citations. The asymmetry is deliberate (§Composition).
              else if (mine)
                Text(
                  message.text ?? '',
                  // kit-ok: F-43 — Ask's own turn at sans 15/22; no kit role names it
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 15,
                    height: 22 / 15,
                    color: t.fg,
                  ),
                )
              // Three sentences, because they are three different facts
              // (ADR-098). A scoped turn that searched the shelf exhaustively
              // can say the shelf has nothing about it; one that filtered a
              // TRUNCATED pool cannot, and saying so anyway would be the
              // screen asserting something false about the shelf.
              else if (message.citations.isEmpty)
                Text(_emptyAnswer(message.scope), style: KitText.meta(context))
              else
                for (var i = 0; i < message.citations.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? AppSpacing.s1 : 8),
                    child: _CitationPill(
                      index: i + 1,
                      citation: message.citations[i],
                      from: from,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

String _emptyAnswer(AskScope? scope) {
  if (scope?.tagId == null) return 'No related passages found.';
  final name = (scope!.title?.isNotEmpty == true) ? scope.title! : 'this shelf';
  return scope.exhaustive
      ? 'No passages on $name relate to that.'
      : 'No passages on $name came up among the closest matches in your '
          'library. A narrower question may reach them.';
}

/// A citation: a bordered pill with a mono index, the document's title, and the
/// stored excerpt — whose extraction markers render as Marker inline (§17.2).
class _CitationPill extends StatelessWidget {
  final int index;
  final AskCitation citation;

  /// The route this conversation is AT, carried onto the Reader so its back
  /// control can name it and return there (ADR-101). Null on a conversation
  /// with no address yet — the first turn, before it has moved to its thread.
  final String? from;

  const _CitationPill({
    required this.index,
    required this.citation,
    this.from,
  });

  /// The Reader this citation opens, with the way back on it (4.65.0,
  /// ADR-101): `?from=` names this conversation, and it is **pushed** rather
  /// than gone to, so the reader's own back gesture lands in the transcript
  /// too. `context.go` REPLACES — it was how this control opened the Reader
  /// until 4.65.0, and a citation that discards the conversation it came from
  /// is the screen throwing away the thing the reader was reading.
  String _readerRoute() {
    final p = citation.chunkId == null ? '' : 'p=${citation.chunkId}';
    final f = from == null ? '' : 'from=${Uri.encodeComponent(from!)}';
    final q = [p, f].where((s) => s.isNotEmpty).join('&');
    return '/reader/${citation.documentId}${q.isEmpty ? '' : '?$q'}';
  }

  /// [_readerRoute]'s query alone, for the §6.4.3 link's address.
  String _readerQuery() {
    final r = _readerRoute();
    final i = r.indexOf('?');
    return i < 0 ? '' : r.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final host = sourceHost(citation.sourceUrl);
    return GestureDetector(
      onTap: citation.documentId == null
          ? null
          : () => context.push(_readerRoute()),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.border),
          borderRadius: AppRadius.pillR(44),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$index',
              style: AppTheme.mono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: t.accentText,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KitText.ui(context, color: t.fg, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  // The excerpt is `chunk.text`, so `[Image: …]` reaches it.
                  // KitMarkedText draws each marker as §17.2 and never strips
                  // one: across production the markers are a median 31.6% of a
                  // marker-bearing chunk (ADR-089).
                  KitMarkedText(
                    citation.excerpt,
                    style: KitText.ui(context, color: t.fgSubtle, height: 19),
                  ),
                  // §5.2's action bar, drawn with the kit's own control — the
                  // reference's three Ask actions rendered as bare browser
                  // buttons because `.pact` was scoped to `.passage` there.
                  if (citation.documentId != null || host != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: [
                        if (citation.documentId != null)
                          KitSourceLink(
                            docId: citation.documentId!,
                            query: _readerQuery(),
                            builder: (context, open) => KitPassageAction(
                              icon: Icons.visibility_outlined,
                              label: 'Open',
                              onTap: open,
                            ),
                          ),
                        // The passage's own source, when there IS one (4.63.0,
                        // ADR-099). A stored file and an image set have no URL
                        // and get no control — §6.4.2 rule 3, say nothing
                        // rather than offer one that goes nowhere.
                        if (host != null) ...[
                          if (citation.documentId != null)
                            const SizedBox(width: AppSpacing.s4),
                          KitPassageAction(
                            icon: Icons.open_in_new,
                            label: host,
                            onTap: () => launchUrlString(
                              citation.sourceUrl!,
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rail's group labels, computed in the READER's own timezone — the rail is
/// the one surface where "today" is a thing they can check against their memory.
String _groupOf(int? ms) {
  if (ms == null) return 'Earlier';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final sameDay =
      d.year == now.year && d.month == now.month && d.day == now.day;
  return sameDay ? 'Today' : 'Earlier';
}

String _entryTime(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  if (_groupOf(ms) == 'Today') {
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

