import 'package:flutter/material.dart';

import '../../models/echo.dart';
import '../../services/analytics.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/error_text.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';

// The sentences are the contract's (screens/reader.md §Echoes, api/echoes.md
// §States) and web's `EchoesPanel.jsx`, byte for byte.
const echoesNothingClose =
    'Nothing elsewhere in your library is close to this yet.';
const echoesNothingToCompare = 'This source has no passages to compare yet.';
const echoesFailed = 'Echoes could not be found.';
const echoesStandfirst =
    'Passages in your other sources that say something close to this one.';
String echoesComparedNote(int compared, int passages) =>
    'Compared $compared of this source’s ${kitCounted(passages, 'passage')}.';

/// The reader route's query for an echo: the passage it opens at (`?p=`,
/// INV-21) and the way back naming this source (§The way back, ADR-101).
String echoReaderQuery(String chunkId, String fromDocId) =>
    'p=${Uri.encodeComponent(chunkId)}'
    '&from=${Uri.encodeComponent('/reader/$fromDocId')}';

/// Reader → Echoes (5.83.0, ADR-255; screens/reader.md §Echoes, kit §43):
/// the passages in the reader's OTHER sources nearest this one's, from the
/// vectors already stored on its chunks — ported from the web reference
/// `pages/reader/EchoesPanel.jsx`.
///
/// **One call, on mount** — and the section mounts on approach, never
/// eagerly (§Continuous scroll) — and none again unless *Try again* asks.
/// Present whether generative AI is on or off: no model writes any of it.
/// The rows are drawn in the order the server gives (the source's own) and
/// never re-sorted, filtered or floored here.
class EchoesPanel extends StatefulWidget {
  final String docId;

  /// An echo was followed: open the reader at [chunkId] of [docId]. The
  /// panel fires `echo_opened` first.
  final void Function(String docId, String chunkId) onOpenEcho;

  /// This source's own passage, asked for by its head: bring it into view in
  /// the Manuscript and flash it. Never a navigation.
  final ValueChanged<String> onShowPassage;

  const EchoesPanel({
    super.key,
    required this.docId,
    required this.onOpenEcho,
    required this.onShowPassage,
  });

  @override
  State<EchoesPanel> createState() => _EchoesPanelState();
}

class _EchoesPanelState extends State<EchoesPanel> {
  EchoesAnswer? _answer;
  String? _error;
  String? _errorRequestId;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EchoesPanel old) {
    super.didUpdateWidget(old);
    if (old.docId != widget.docId) _load();
  }

  Future<void> _load() async {
    final attempt = ++_attempt;
    setState(() {
      _answer = null;
      _error = null;
      _errorRequestId = null;
    });
    try {
      final res = await Api.instance.findEchoes(widget.docId);
      if (!mounted || attempt != _attempt) return;
      setState(() => _answer = EchoesAnswer.fromJson(res));
    } on ApiException catch (e) {
      if (!mounted || attempt != _attempt) return;
      // The server's sentence, kept: a 404 for a source gone and a 500 are
      // different answers (§14.1).
      setState(() {
        _error = e.message;
        _errorRequestId = e.requestId;
      });
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() => _error = describeSdkError(e));
    }
  }

  void _open(EchoTarget echo) {
    Analytics.track('echo_opened');
    widget.onOpenEcho(echo.docId, echo.chunkId);
  }

  @override
  Widget build(BuildContext context) {
    // The section's own eyebrow; not drawn in D (the §31 head names it).
    final intro = ReaderUi(context).intro('Echoes');
    Widget panel(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [intro, ...children],
        );

    final error = _error;
    if (error != null) {
      // A failure is never an empty state: §14.1, in the section, and the
      // reader around it stands.
      return panel([
        KitFailureBlock(
          sentence: echoesFailed,
          detail: error,
          requestId: _errorRequestId,
          onRetry: _load,
        ),
      ]);
    }

    final answer = _answer;
    if (answer == null) {
      // §29's skeleton while the call is out, never a sentence.
      return panel(const [
        KitEchoStandfirst(echoesStandfirst),
        KitSkeletonLines(top: 0, lines: [
          KitSkelLine(0.7),
          KitSkelLine(),
          KitSkelLine(0.4),
          KitSkelLine(0.6),
          KitSkelLine(),
          KitSkelLine(0.4),
        ]),
      ]);
    }

    // Nothing was compared: the note alone, no standfirst.
    if (answer.compared == 0) {
      return panel(const [KitEchoNote(echoesNothingToCompare)]);
    }

    return panel([
      const KitEchoStandfirst(echoesStandfirst),
      if (answer.echoes.isEmpty)
        const KitEchoNote(echoesNothingClose, afterStandfirst: true)
      else
        KitEchoList(pairs: [
          for (final g in echoGroups(answer.echoes))
            KitEchoPair(
              key: ValueKey('echo-pair-${g.passage.chunkId}'),
              chunkIndex: g.passage.chunkIndex,
              excerpt: g.passage.excerpt,
              onShowPassage: () => widget.onShowPassage(g.passage.chunkId),
              echoes: [
                for (final e in g.echoes)
                  KitEcho(
                    docId: e.docId,
                    chunkId: e.chunkId,
                    excerpt: e.excerpt,
                    type: e.type,
                    title: e.title,
                    query: echoReaderQuery(e.chunkId, widget.docId),
                    onOpen: () => _open(e),
                  ),
              ],
            ),
        ]),
      if (answer.partial)
        KitEchoNote(echoesComparedNote(answer.compared, answer.passages)),
    ]);
  }
}
