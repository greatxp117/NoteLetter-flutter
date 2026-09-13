import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/ask_thread.dart';
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
  const ChatPage({super.key});

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
    _controller.addListener(() {
      // Editing withdraws the last rejection — the text it referred to is
      // being changed.
      context.read<ChatNotifier>().clearError();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final notifier = context.read<ChatNotifier>();
    final ok = await notifier.ask(_controller.text);
    // Write BEFORE you move (ADR-022): the box clears only once the turn has
    // been recorded. On a rejection the question stays where the reader can
    // correct it, beside the §14.2 line that refused it.
    if (ok) _controller.clear();
    if (mounted) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ask = context.watch<ChatNotifier>();
    final t = Tokens.of(context);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.frameGutterCompact,
                  AppSpacing.s6, AppSpacing.frameGutterCompact, 0),
              child: ScreenHeader(
                eyebrow: 'Grounded in your library',
                title: 'Ask your library',
                standfirst:
                    'Find what you’ve read on a topic — every result traces '
                    'back to a passage.',
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
            placeholder: 'Ask your library anything…',
            busy: ask.sending,
            error: ask.error,
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
      onNew: () {
        context.read<ChatNotifier>().newConversation();
        setState(() => _railOpen = false);
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
        time: _entryTime(thread.updatedAt),
        preview: thread.preview,
        active: thread.id == ask.activeId,
        onTap: () {
          context.read<ChatNotifier>().openThread(thread.id);
          setState(() => _railOpen = false);
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
    await KitConfirm.show(
      context,
      title: 'Delete “$name”?',
      body: 'The questions in this conversation and the passages it found are '
          'removed. Nothing leaves your library — a conversation cites your '
          'passages, it does not hold them.',
      confirmLabel: 'Delete conversation',
      cancelLabel: 'Keep it',
      onConfirm: () => ask.deleteThread(id),
    );
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

    // §7 — an offer, not an apology. It stands only when nothing is open AND
    // nothing is in flight; a question already sent belongs in the transcript,
    // not behind a suggestion stack.
    if (ask.messages.isEmpty && !ask.sending) {
      return KitPage(
        width: KitFrameWidth.reading,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s8),
          child: KitEmptyState(
            icon: Icons.auto_awesome,
            title: 'Ask your library a question',
            standfirst:
                'Type a topic or question and NoteLetter will surface the '
                'passages that relate to it.',
            suggestions: [
              for (final p in _prompts)
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
              child: _AskMessageRow(message: m),
            ),
          // The turn in flight: the question as the reader wrote it, then the
          // searching line. Restoring a STORED conversation never draws this —
          // `pending` is only ever set by a request this screen just made.
          if (ask.pending != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: _AskMessageRow(
                message: AskMessage(
                  id: '_pending',
                  role: AskRole.user,
                  text: ask.pending,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: _AskMessageRow(
                message: const AskMessage(id: '_searching', role: AskRole.library),
                searching: true,
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

  const _AskMessageRow({required this.message, this.searching = false});

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
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.chromeFg,
                  ),
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
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.fgMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.s1),
              if (searching)
                Text('Searching…', style: KitText.meta(context))
              // The reader's text is UI sans 15/22; the app's side is its
              // citations. The asymmetry is deliberate (§Composition).
              else if (mine)
                Text(
                  message.text ?? '',
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 15,
                    height: 22 / 15,
                    color: t.fg,
                  ),
                )
              else if (message.citations.isEmpty)
                Text('No related passages found.', style: KitText.meta(context))
              else
                for (var i = 0; i < message.citations.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? AppSpacing.s1 : 8),
                    child: _CitationPill(
                      index: i + 1,
                      citation: message.citations[i],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A citation: a bordered pill with a mono index, the document's title, and the
/// stored excerpt — whose extraction markers render as Marker inline (§17.2).
class _CitationPill extends StatelessWidget {
  final int index;
  final AskCitation citation;

  const _CitationPill({required this.index, required this.citation});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return GestureDetector(
      onTap: citation.documentId == null
          ? null
          : () => context.go('/reader/${citation.documentId}'
              '${citation.chunkId == null ? '' : '?p=${citation.chunkId}'}'),
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
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // The excerpt is `chunk.text`, so `[Image: …]` reaches it.
                  // KitMarkedText draws each marker as §17.2 and never strips
                  // one: across production the markers are a median 31.6% of a
                  // marker-bearing chunk (ADR-089).
                  KitMarkedText(
                    citation.excerpt,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 13,
                      height: 19 / 13,
                      color: t.fgSubtle,
                    ),
                  ),
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

