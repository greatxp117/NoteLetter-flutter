/// Summary-style prompt copy, limits and the 4.4.0 control composition.
///
/// Port of the web reference `src/pages/settings/summaryPrompt.js`. The
/// fragment strings below are **byte-identical to web on purpose** — positions
/// are recovered from a stored prompt by exact match over the composition
/// space, and the same account's prompt is read by every client. A "tidied"
/// apostrophe or a trimmed space here would make a prompt composed on web
/// render as hand-authored Custom text on Flutter: no error, no failing test,
/// just a control that quietly stops recognising its own output.
///
/// [defaultSummaryPrompt] mirrors the backend's default instruction verbatim
/// (spec/api/summary.md states it normatively). It is DISPLAY copy only: the
/// field prefills with it so the reader edits the existing stance rather than
/// authoring one from nothing. The server always owns the operative default —
/// an absent `summaryPrompt` means the backend uses its own copy — so drift
/// here is cosmetic, never behavioural.
library;

const String defaultSummaryPrompt =
    'a substantive free-form summary in flowing prose, typically 5-10 sentences; '
    "structure it around the document's own content rather than a fixed template: "
    'if the document makes several distinct points, arguments, or steps, cover each '
    'of them briefly in order; for a narrative or single-argument piece, trace the '
    'argument instead';

const int summaryPromptMaxChars = 2000;

/// The value a save should send, or null when the draft is not sendable.
/// Empty/whitespace is deliberately unsendable — the contract has no "empty
/// prompt" state (the empty string is a 400); resetting to the default is its
/// own control and sends `summaryPrompt: null`.
String? sendablePrompt(String? draft) {
  final text = (draft ?? '').trim();
  if (text.isEmpty || text.length > summaryPromptMaxChars) return null;
  return text;
}

class StyleOption {
  final String id;
  final String label;

  /// null marks this dimension's DEFAULT position — it contributes no text, and
  /// all-defaults therefore composes to null (a reset).
  final String? fragment;
  const StyleOption(this.id, this.label, this.fragment);
}

class StyleDimension {
  final String id;
  final String label;
  final List<StyleOption> options;
  const StyleDimension(this.id, this.label, this.options);
}

const List<StyleDimension> styleDimensions = [
  StyleDimension('balance', 'Draws from', [
    StyleOption('paraphrase', 'Paraphrase', null),
    StyleOption('mixed', 'Prose + quotes',
        'Weave two to four short direct quotations from the source into the '
        'summary, choosing the lines that best carry its voice; paraphrase the rest.'),
    StyleOption('quotes', 'Mostly quotes',
        'Build the summary mostly from direct quotations of the source’s own '
        'words — pick the lines that best carry each point, with only brief '
        'connecting prose between them.'),
  ]),
  StyleDimension('length', 'Length', [
    StyleOption('brief', 'Brief',
        'Keep the summary brief: two or three sentences carrying only the core point.'),
    StyleOption('standard', 'Standard', null),
    StyleOption('thorough', 'Thorough',
        'Make the summary thorough: ten to fifteen sentences, with room for '
        'secondary points and nuance.'),
  ]),
  StyleDimension('tone', 'Tone', [
    StyleOption('neutral', 'Neutral', null),
    StyleOption('conversational', 'Conversational',
        'Write in a relaxed, conversational register, as if explaining the piece to a friend.'),
    StyleOption('scholarly', 'Scholarly', 'Write in a precise, scholarly register.'),
  ]),
];

Map<String, String> get defaultChoices => {
      for (final d in styleDimensions)
        d.id: d.options.firstWhere((o) => o.fragment == null).id,
    };

/// choices -> the prompt string to store, or null when every dimension sits at
/// its default. **All-defaults composes to a reset**, never to a stored copy of
/// the default text: absent means default, and a stored copy would stop
/// tracking the default if it ever moved.
String? composePrompt(Map<String, String> choices) {
  final parts = <String>[];
  for (final dim in styleDimensions) {
    final id = choices[dim.id];
    final opt = dim.options.where((o) => o.id == id).firstOrNull;
    if (opt?.fragment != null) parts.add(opt!.fragment!);
  }
  return parts.isEmpty ? null : parts.join(' ');
}

/// stored prompt text -> choices, or **null when it is not a composed prompt**
/// (i.e. hand-authored). A non-match must render as the free-text editor — it
/// is never lossily snapped to the nearest positions. The default instruction
/// text itself reads as all-defaults, so a prompt saved verbatim from the
/// 4.3.0 textarea round-trips into the toggles.
Map<String, String>? parsePrompt(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return {...defaultChoices};
  if (t == defaultSummaryPrompt) return {...defaultChoices};

  Map<String, String>? walk(int i, Map<String, String> choices) {
    if (i == styleDimensions.length) {
      return composePrompt(choices) == t ? {...choices} : null;
    }
    for (final opt in styleDimensions[i].options) {
      final hit = walk(i + 1, {...choices, styleDimensions[i].id: opt.id});
      if (hit != null) return hit;
    }
    return null;
  }

  return walk(0, {});
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
