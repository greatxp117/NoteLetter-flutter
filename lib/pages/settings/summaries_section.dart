import 'package:flutter/material.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import 'summary_prompt.dart';

/// Settings → Summaries (spec/screens/settings.md 4.3.0 + 4.4.0, ADR-040):
/// the summary-style prompt, in two modes over **one stored value**.
///
/// Simple = three segmented controls that COMPOSE into `summaryPrompt`
/// (positions recovered by exact match; all-defaults composes to a reset).
/// Custom = the free-text field, prefilled so the reader edits the existing
/// stance rather than authoring one from nothing. A hand-authored prompt
/// renders as Custom and is never silently reformatted or lossily snapped to
/// the nearest positions — **mode switching writes nothing**.
///
/// Write-before-move (2.29.0): local edits are cleared only after the PUT
/// resolves, so the displayed value always comes from the subscription. A
/// control that adopted the new value first would hide a failed save
/// completely — it would revert only on reload.
class SummariesSection extends StatefulWidget {
  const SummariesSection({super.key});

  @override
  State<SummariesSection> createState() => _SummariesSectionState();
}

class _SummariesSectionState extends State<SummariesSection> {
  String? _stored; // the confirmed prompt; null = default in effect
  bool _loaded = false;
  String? _draftText; // custom-mode edit in flight
  Map<String, String>? _draftChoices; // simple-mode edit in flight
  String? _modeOverride; // user-chosen mode
  bool _busy = false;
  String? _error;

  final _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.subscribeSummarySettings().listen((p) {
      if (!mounted) return;
      setState(() {
        _stored = p;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _put(String? value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.updateSummarySettings(value);
      if (!mounted) return;
      // Adopt the subscription's confirmed value — never a local guess.
      setState(() {
        _draftText = null;
        _draftChoices = null;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'The style could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearEdits() {
    setState(() {
      _draftText = null;
      _draftChoices = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Don't render a field that is about to change under the reader.
    if (!_loaded) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    final storedPrompt = _stored;
    final custom = storedPrompt != null;
    final storedChoices = parsePrompt(storedPrompt); // null = hand-authored
    final mode = _modeOverride ?? (storedChoices != null ? 'simple' : 'custom');

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Summaries',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'How each new source’s summary is written. It applies to sources you '
                'add from now on; an existing source’s summary changes only when you '
                'regenerate it from its Summary tab.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 16),
              if (mode == 'simple')
                ..._simpleMode(theme, muted, storedChoices, storedPrompt)
              else
                ..._customMode(theme, muted, custom, storedChoices, storedPrompt),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _simpleMode(ThemeData theme, Color muted,
      Map<String, String>? storedChoices, String? storedPrompt) {
    final choices = _draftChoices ?? storedChoices ?? defaultChoices;
    final composed = composePrompt(choices); // null = all defaults
    final dirty = composed != storedPrompt;
    final previewText = composed ?? defaultSummaryPrompt;

    return [
      for (final dim in styleDimensions) ...[
        Text(dim.label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in dim.options)
              ChoiceChip(
                label: Text(o.label),
                selected: choices[dim.id] == o.id,
                onSelected: _busy
                    ? null
                    : (_) => setState(() =>
                        _draftChoices = {...choices, dim.id: o.id}),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      // The instruction the choices compose into — SHOWN, not hidden, because
      // it is exactly what gets saved and what the model reads. Hiding it would
      // let the controls claim a precision the prompt does not have.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? AppColors.surfaceSunkenDark
              : AppColors.surfaceSunkenLight,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(previewText,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, fontStyle: FontStyle.italic)),
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        Text(_error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.critical)),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(
            onPressed: (_busy || !dirty) ? null : () => _put(composed),
            child: Text(_busy ? 'Saving…' : 'Save style'),
          ),
          if (_draftChoices != null)
            TextButton(
                onPressed: _busy ? null : _clearEdits,
                child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              // Switching mode writes nothing.
              _textCtrl.text = composed ?? storedPrompt ?? defaultSummaryPrompt;
              setState(() {
                _draftText = _textCtrl.text;
                _modeOverride = 'custom';
              });
            },
            child: const Text('Fine-tune by hand →'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _customMode(ThemeData theme, Color muted, bool custom,
      Map<String, String>? storedChoices, String? storedPrompt) {
    final effectiveText = storedPrompt ?? defaultSummaryPrompt;
    if (_draftText == null && _textCtrl.text != effectiveText) {
      _textCtrl.text = effectiveText;
    }
    final shownText = _draftText ?? effectiveText;
    final textDirty = _draftText != null && _draftText!.trim() != effectiveText;
    final sendable = sendablePrompt(shownText);

    return [
      TextField(
        controller: _textCtrl,
        maxLines: 5,
        minLines: 3,
        maxLength: summaryPromptMaxChars,
        enabled: !_busy,
        style: theme.textTheme.bodySmall,
        decoration: const InputDecoration(
          labelText: 'Summary style prompt',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _draftText = v),
      ),
      Text(
        '${custom ? 'Custom style in effect.' : 'Using the default summary style.'}'
        ' Up to $summaryPromptMaxChars characters.',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        Text(_error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.critical)),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(
            onPressed: (_busy || !textDirty || sendable == null)
                ? null
                : () => _put(sendable),
            child: Text(_busy ? 'Saving…' : 'Save style'),
          ),
          if (textDirty)
            TextButton(
                onPressed: _busy ? null : _clearEdits,
                child: const Text('Cancel')),
          // Reset sends null — there is no "empty prompt" state to offer.
          if (custom)
            TextButton(
                onPressed: _busy ? null : () => _put(null),
                child: const Text('Reset to default')),
          TextButton(
            onPressed: () {
              // Adopt matching positions when the text is (or reverts to) a
              // composed shape; otherwise start from the stored positions or
              // the defaults. Nothing is written by switching modes.
              final parsed = parsePrompt(shownText.trim());
              setState(() {
                _draftChoices = parsed ?? storedChoices ?? defaultChoices;
                _draftText = null;
                _modeOverride = 'simple';
              });
            },
            child: const Text('Use simple controls →'),
          ),
        ],
      ),
    ];
  }
}
