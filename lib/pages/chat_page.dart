import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../models/ask_thread.dart';
import '../shared/source_host.dart';
import '../state/tags_notifier.dart';
import '../state/chat_notifier.dart';
import '../theme/app_motion.dart';
import '../widgets/kit/kit.dart';

/// Ask — conversational retrieval over the reader's own notes, answered in the
/// app's own words with the passages quoted (5.30.0, ADR-187), and the
/// conversations kept (4.53.0, ADR-090; `spec/screens/ask.md`).
///
/// Composition — direction D (`screens/ask.md` §Composition; web
/// `pages/AskView.jsx`): **the conversation is the page.** The D frame
/// ([KitDPage]): its folio, the open conversation's title on the masthead, and
/// the 5.30.0 standfirst; the questions and what answered them in the column —
/// each answer §25's written answer ([KitAskAnswer]) over its citations as a
/// ruled register; the §38 composer docked at the column's foot
/// ([KitDPage.dock]). The conversations are the sheet (§29; on a phone its
/// running head, §30): §9's list with §9.1's rename and delete and §9.2's
/// scope. *New conversation* is the page's one action while a conversation is
/// open. The empty state is §37's; a refused turn is §14.2 in the turn; a
/// failed read is §14.1 in its own region; a citation's excerpt and a quote
/// draw their extraction markers inline (§17.2).
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

/// The conversations read's window (`subscribeAskThreads`' limit): at it, the
/// running head's count is a floor (`100+`), never a total.
const _threadsWindow = 100;

/// How long a citation a marker pointed at stays marked (kit §25).
const _markFor = Duration(milliseconds: 1600);

/// The room the docked composer takes at the viewport's foot: a citation
/// revealed by a marker must land above it, not under it.
const _dockRoom = 120.0;

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _composer = FocusNode();
  final _scroll = ScrollController();

  /// The citation a §25 marker just pointed at (`{messageId}:{n}`), marked for
  /// [_markFor] so the eye lands on it after the scroll.
  String? _marked;
  Timer? _markTimer;
  final Map<String, GlobalKey> _citeKeys = {};

  /// The transcript's end, so a turn just sent can be brought into view.
  final GlobalKey _end = GlobalKey(debugLabel: 'ask-end');

  @override
  void initState() {
    super.initState();
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
    _markTimer?.cancel();
    _controller.dispose();
    _composer.dispose();
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
    if (question.isEmpty || notifier.sending) return;
    _controller.clear();
    // The turn is on screen from the moment it is sent; bring it into view
    // then, not when the answer lands.
    final asked = notifier.ask(question);
    _revealEnd();
    final threadId = await asked;
    if (!mounted) return;
    // The first turn MOVES to the thread the endpoint recorded — after it is
    // recorded, never before (ADR-022, ADR-101).
    if (threadId != null) context.go('/ask/thread/$threadId');
    _revealEnd();
  }

  /// Re-send the turn that is on screen. It is not a draft — putting it back
  /// in the composer would be the screen saying it was never asked (ADR-097).
  Future<void> _retry() async {
    final threadId = await context.read<ChatNotifier>().retry();
    if (!mounted) return;
    if (threadId != null) context.go('/ask/thread/$threadId');
  }

  /// "New conversation" LEAVES the scope and the open thread — one navigation
  /// covers both, because both are `/ask` (ADR-098, ADR-101). A control that
  /// stayed scoped would offer the whole library while asking a shelf.
  void _newConversation() {
    context.go('/ask');
    _composer.requestFocus();
  }

  /// A suggested prompt fills the composer; asking is still the reader's.
  void _fillPrompt(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    _composer.requestFocus();
  }

  /// The address this screen is AT — one of ADR-101's three forms. A citation
  /// hands it to the Reader as `?from=`, so the Reader's back control can name
  /// this conversation and return to it.
  String _routePath() {
    if (widget.threadId != null) return '/ask/thread/${widget.threadId}';
    if (widget.scopeTagId != null) return '/ask/shelf/${widget.scopeTagId}';
    return '/ask';
  }

  /// Bring the transcript's end — the turn just sent, or its refusal — into
  /// view above the docked composer, and only if it is not already: a short
  /// conversation does not move, and the page never jumps past the column to
  /// its footer.
  void _revealEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final end = _end.currentContext?.findRenderObject();
      if (!mounted || !_scroll.hasClients || end is! RenderBox) return;
      final vp = _scroll.position.context.storageContext.findRenderObject();
      if (vp is! RenderBox) return;
      final y = end.localToGlobal(Offset.zero, ancestor: vp).dy;
      final room = _scroll.position.viewportDimension - _dockRoom;
      if (y <= room) return;
      final p = _scroll.position;
      _scroll.animateTo(
        (p.pixels + y - room).clamp(p.minScrollExtent, p.maxScrollExtent),
        duration: KitD.dur(context, AppMotion.durSlow),
        curve: AppMotion.easeQuill,
      );
    });
  }

  GlobalKey _citeKey(String key) => _citeKeys.putIfAbsent(key, GlobalKey.new);

  /// §25: a marker scrolls to its citation — only as far as it must, landing
  /// clear of the docked composer — and marks it for a moment.
  void _showCite(String messageId, int n) {
    final key = '$messageId:$n';
    final ctx = _citeKeys[key]?.currentContext;
    if (ctx != null && _scroll.hasClients) {
      final box = ctx.findRenderObject();
      final vp = _scroll.position.context.storageContext.findRenderObject();
      if (box is RenderBox && vp is RenderBox) {
        final top = box.localToGlobal(Offset.zero, ancestor: vp).dy;
        final bottom = top + box.size.height;
        final room = _scroll.position.viewportDimension - _dockRoom;
        if (top < 0 || bottom > room) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.25,
            duration: KitD.dur(context, AppMotion.durSlow),
            curve: AppMotion.easeQuill,
          );
        }
      }
    }
    setState(() => _marked = key);
    _markTimer?.cancel();
    _markTimer = Timer(_markFor, () {
      if (mounted) setState(() => _marked = null);
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
    final scope = _scopeName(ask);
    final open = ask.activeId == null ? null : ask.activeThread;
    final openTitle =
        open == null ? null : (open.title.isEmpty ? 'Untitled' : open.title);
    final title = openTitle ?? (scope == null ? 'Ask Your Library' : 'Ask $scope');
    // The folio names what is searched, then — while a conversation is open —
    // its time (§9's entry time). The kit sets the no-break space before
    // each dot.
    final folio = [
      'Ask',
      scope == null ? 'Grounded in your library' : 'Grounded in one shelf · $scope',
      if (open != null && _entryTime(open.updatedAt).isNotEmpty)
        _entryTime(open.updatedAt),
    ].join(' · ');
    // Every thread the read returns is the reader's own (INV-02) and a row in
    // the sheet, so this counts rows; at the read's window it is a floor.
    final count = ask.loadingThreads || ask.railError != null
        ? null
        : (ask.threads.length >= _threadsWindow
            ? '$_threadsWindow+'
            : '${ask.threads.length}');

    return KitDPage(
      folio: folio,
      title: title,
      titleWidget: KitAskTitle(title),
      // 5.30.0's sentences (screens/ask.md §Composition, Copy): Ask writes an
      // answer that quotes its passages. D keeps them, not the prototype's
      // 5.28 sentence from before the written answer.
      stand: scope == null
          ? 'Ask about what you’ve read — answers quote the passages they '
              'draw on.'
          : 'Only passages on this shelf are read — every answer quotes the '
              'passages it draws on.',
      action: ask.activeId == null
          ? null
          : KitPageAction(
              label: 'New conversation',
              short: 'New',
              icon: Icons.add,
              onPressed: _newConversation,
            ),
      controller: _scroll,
      sheet: KitDSheet(
        label: 'Conversations',
        peek: KitAskPeek(title: openTitle ?? 'Conversations', count: count),
        // Choosing an entry or *New conversation* folds the running head.
        foldOnPick: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const KitDLabel('Conversations', first: true),
            ..._conversations(context, ask),
          ],
        ),
      ),
      dock: KitAskComposer(
        controller: _controller,
        focusNode: _composer,
        label: scope == null ? 'Ask your library' : 'Ask $scope',
        placeholder:
            scope == null ? 'Ask your library anything…' : 'Ask $scope anything…',
        busy: ask.sending,
        onSubmit: _send,
      ),
      child: _transcript(context, ask, scope),
    );
  }

  // ── The sheet: the conversations ─────────────────────────────────────────

  List<Widget> _conversations(BuildContext context, ChatNotifier ask) {
    final out = <Widget>[
      KitAskNewConversation(
        active: ask.activeId == null,
        onTap: _newConversation,
      ),
    ];
    // INV-24 in the list's own region (ADR-097): a list that could not be
    // read is §14.1, never the no-threads state — which says the reader has
    // no conversations.
    if (ask.railError != null) {
      out.add(KitFailureBlock(
        sentence: 'Your conversations could not be loaded.',
        detail: ask.railError!,
      ));
      return out;
    }
    if (ask.loadingThreads) {
      out.add(const KitSkeletonLines(lines: [
        KitSkelLine(0.7),
        KitSkelLine(0.6),
        KitSkelLine(),
        KitSkelLine(0.7),
        KitSkelLine(0.5),
      ]));
      return out;
    }
    String? group;
    for (final thread in ask.threads) {
      final label = _groupOf(thread.updatedAt);
      if (label != group) {
        out.add(KitAskGroupLabel(label));
        group = label;
      }
      out.add(_entry(context, ask, thread));
    }
    return out;
  }

  Widget _entry(BuildContext context, ChatNotifier ask, AskThread thread) {
    final name = thread.title.isEmpty ? 'Untitled' : thread.title;
    return KitAskConvo(
      key: ValueKey('ask-convo-${thread.id}'),
      title: name,
      // §9.2 — nothing at all when the conversation is unscoped.
      scope: thread.tagId == null
          ? null
          : (thread.tagTitle?.isNotEmpty == true ? thread.tagTitle : 'shelf'),
      time: _entryTime(thread.updatedAt),
      preview: thread.preview,
      active: thread.id == ask.activeId,
      // Opening a conversation is a NAVIGATION (ADR-101) — and only to a
      // DIFFERENT one: `go` to the address the screen is already at rebuilds
      // the page, and a rename field open in it would be torn down mid-edit.
      onOpen: () {
        if (thread.id != widget.threadId) {
          context.go('/ask/thread/${thread.id}');
        }
      },
      // §9.1 (4.55.0, ADR-091): rename in place, and delete behind §18.
      actions: [
        KitAskConvoAction(
          icon: Icons.edit_outlined,
          label: 'Rename “$name”',
          onPressed: () => context.read<ChatNotifier>().startRename(thread.id),
        ),
        KitAskConvoAction(
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
  }

  /// §9.1: a destructive entry action confirms, and the confirmation names what
  /// is lost AND what is not. A conversation CITES passages; it does not hold
  /// them, so deleting one takes nothing out of the library.
  /// §18 (4.56.0, ADR-092): the delete runs inside the panel and its rejection
  /// renders there; `KitConfirm` reports true only on SUCCESS. Deleting the
  /// open conversation returns to `/ask` — a URL naming a deleted thread is
  /// the address bar pointing at nothing (ADR-101).
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
    if (!mounted || !wasOpen || deleted != true) return;
    context.go('/ask');
  }

  // ── The column: the transcript ───────────────────────────────────────────

  Widget _transcript(BuildContext context, ChatNotifier ask, String? scope) {
    // INV-24: a transcript we could not READ is not an empty conversation —
    // the empty state would say the reader had asked nothing (ADR-097).
    if (ask.threadError != null) {
      return KitFailureBlock(
        sentence: 'This conversation could not be loaded.',
        detail: ask.threadError!,
        onRetry: () => context.read<ChatNotifier>().retryThread(),
      );
    }
    // Restoring a conversation issues NO request, so it never draws the
    // thinking line (`screens/ask.md` §States): skeleton lines until it is
    // read.
    if (ask.activeId != null && !ask.messagesLoaded && ask.sentQuestion == null) {
      return const KitSkeletonLines(
        top: 0,
        lines: [
          KitSkelLine(0.6, true),
          KitSkelLine(),
          KitSkelLine(),
          KitSkelLine(0.7),
          KitSkelLine(),
          KitSkelLine(0.5),
        ],
      );
    }
    // §37 — an offer, not an apology. It stands only when nothing is open AND
    // nothing has been sent. The suggestions are about a WHOLE library, so a
    // shelf's state has none (ADR-098).
    if (ask.messages.isEmpty && ask.sentQuestion == null) {
      return KitEmptyState(
        icon: KitQuill.icon,
        title: scope == null
            ? 'Ask your library a question'
            : 'Ask $scope a question',
        standfirst: scope == null
            ? 'Ask a question and NoteLetter will answer from your notes, '
                'quoting the passages it draws on.'
            : 'Ask a question and NoteLetter will answer from $scope, quoting '
                'the passages it draws on.',
        suggestions: [
          for (final p in scope == null ? _prompts : const <String>[])
            KitSuggestion(
              icon: KitSparkle.icon,
              label: p,
              onTap: () => _fillPrompt(p),
            ),
        ],
      );
    }

    final from = _routePath();
    final turns = <Widget>[];
    for (final m in ask.messages) {
      if (m.role == AskRole.user) {
        turns.add(KitAskQuestion(m.text ?? '', first: turns.isEmpty));
      } else {
        turns.add(_reply(m, from));
      }
    }
    // The turn the reader SENT (ADR-097): here from the moment it goes until
    // its own stored message arrives to replace it — and a refusal leaves it
    // here too, with the server's sentence and a retry that re-sends THIS
    // turn. Restoring a stored conversation never draws it.
    final sent = ask.sentQuestion;
    if (sent != null) {
      turns.add(KitAskQuestion(sent, first: turns.isEmpty));
      final refused = ask.sentError;
      turns.add(refused == null
          // The wait covers the answer being written too (5.30.0).
          ? const KitAskReply(line: 'Reading your notes…')
          : KitAskReply(
              failure: KitFailureInline(refused, dense: true),
              retry: KitButton.primary('Try again', onPressed: _retry),
            ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [...turns, SizedBox(key: _end, height: 0)],
    );
  }

  /// The library's turn: the written answer (or its note) over the citations
  /// as a ruled register — or, with no citations, which of the three empties
  /// it is.
  Widget _reply(AskMessage m, String from) {
    if (m.citations.isEmpty) return KitAskReply(line: _emptyAnswer(m.scope));
    return KitAskReply(
      answer: m.answer,
      note: m.answerNote,
      cited: m.citations,
      onCite: (n) => _showCite(m.id, n),
      citations: KitAskCitations(children: [
        for (var i = 0; i < m.citations.length; i++)
          KitAskCitation(
            key: _citeKey('${m.id}:${i + 1}'),
            index: i + 1,
            title: m.citations[i].title,
            excerpt: m.citations[i].excerpt,
            sourceType: m.citations[i].sourceType,
            marked: _marked == '${m.id}:${i + 1}',
            actions: _citeActions(m.citations[i], from),
          ),
      ]),
    );
  }

  /// A citation's actions: *Open* — a §6.4.3 link to the Reader, carrying
  /// `?from=` so its back control returns to this conversation (ADR-101) —
  /// and, when the passage has one, its own source NAMED by host (4.63.0,
  /// ADR-099). A stored file and an image set have no URL and get no control
  /// (§6.4.2 rule 3: say nothing rather than offer one that goes nowhere).
  List<Widget> _citeActions(AskCitation c, String from) {
    final host = sourceHost(c.sourceUrl);
    final query = [
      if (c.chunkId != null) 'p=${c.chunkId}',
      'from=${Uri.encodeComponent(from)}',
    ].join('&');
    return [
      if (c.documentId != null)
        KitSourceLink(
          docId: c.documentId!,
          query: query,
          builder: (context, open) => KitPassageAction(
            icon: Icons.visibility_outlined,
            label: 'Open',
            onTap: open,
          ),
        ),
      if (host != null)
        KitPassageAction(
          icon: Icons.open_in_new,
          label: host,
          maxWidth: 160,
          onTap: () => launchUrlString(
            c.sourceUrl!,
            mode: LaunchMode.externalApplication,
          ),
        ),
    ];
  }
}

/// Three sentences, because they are three different facts (ADR-098). A
/// scoped turn that searched the shelf exhaustively can say the shelf has
/// nothing about it; one that filtered a TRUNCATED pool cannot, and saying so
/// anyway would be the screen asserting something false about the shelf.
String _emptyAnswer(AskScope? scope) {
  if (scope?.tagId == null) return 'No related passages found.';
  final name = (scope!.title?.isNotEmpty == true) ? scope.title! : 'this shelf';
  return scope.exhaustive
      ? 'No passages on $name relate to that.'
      : 'No passages on $name came up among the closest matches in your '
          'library. A narrower question may reach them.';
}

/// The sheet's group labels, computed in the READER's own timezone — the list
/// is the one surface where "today" is a thing they can check against their
/// memory.
String _groupOf(int? ms) {
  if (ms == null) return 'Earlier';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final sameDay =
      d.year == now.year && d.month == now.month && d.day == now.day;
  return sameDay ? 'Today' : 'Earlier';
}

/// §9's entry time: the clock today, the date before.
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
