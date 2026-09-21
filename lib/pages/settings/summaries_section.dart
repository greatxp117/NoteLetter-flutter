import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/kit/kit.dart';
import 'summary_prompt.dart';
import '../../services/error_text.dart';

/// Settings → Summaries (spec/screens/settings.md 4.3.0 + 4.4.0, ADR-040):
/// the summary-style prompt, in two modes over **one stored value**.
///
/// Simple = three segmented controls (§6.8) that COMPOSE into `summaryPrompt`
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
///
/// Composition (settings.md §Composition): one §3 section header over a
/// raised row list holding one setting row, whose control strip is the mode's
/// own controls. The rejection is a §14.2 line at the control; a failed READ
/// of the stored style is a §14.1 block (INV-24), never the default rendered
/// as if it were the reader's choice.
class SummariesSection extends StatefulWidget {
  const SummariesSection({super.key});

  @override
  State<SummariesSection> createState() => _SummariesSectionState();
}

class _SummariesSectionState extends State<SummariesSection> {
  String? _stored; // the confirmed prompt; null = default in effect
  bool _loaded = false;
  String? _subError; // INV-24: the subscription failed, not "no style"
  String? _draftText; // custom-mode edit in flight
  Map<String, String>? _draftChoices; // simple-mode edit in flight
  String? _modeOverride; // user-chosen mode
  bool _busy = false;
  String? _error;

  final _textCtrl = TextEditingController();
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirestoreService.instance.subscribeSummarySettings().listen((p) {
      if (!mounted) return;
      setState(() {
        _stored = p;
        _subError = null;
        _loaded = true;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _subError = describeSdkError(e);
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
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

    final Widget body;
    if (_subError != null) {
      body = KitFailureBlock(
        sentence: 'Your summary settings could not be read.',
        detail: _subError!,
      );
    } else {
      final storedPrompt = _stored;
      final storedChoices = parsePrompt(storedPrompt); // null = hand-authored
      final mode =
          _modeOverride ?? (storedChoices != null ? 'simple' : 'custom');
      body = KitRowList(
        raised: true,
        rows: [
          KitSettingRow(
            icon: Icons.edit_outlined,
            title: 'Summary style',
            description:
                'How each new source’s summary is written. It applies to '
                'sources you add from now on; an existing source’s summary '
                'changes only when you regenerate it from its Summary tab.',
            below: mode == 'simple'
                ? _simpleMode(storedChoices, storedPrompt)
                : _customMode(storedChoices, storedPrompt),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Summaries'),
        body,
      ],
    );
  }

  Widget _simpleMode(Map<String, String>? storedChoices, String? storedPrompt) {
    final choices = _draftChoices ?? storedChoices ?? defaultChoices;
    final composed = composePrompt(choices); // null = all defaults
    final dirty = composed != storedPrompt;
    final previewText = composed ?? defaultSummaryPrompt;
    final effectiveText = storedPrompt ?? defaultSummaryPrompt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dim in styleDimensions) ...[
          const SizedBox(height: 4),
          KitRowNote(dim.label),
          const SizedBox(height: 5),
          KitSegmented(
            segments: [for (final o in dim.options) KitSegment(o.label)],
            selected: dim.options.indexWhere((o) => o.id == choices[dim.id]),
            onChanged: _busy
                ? null
                : (i) => setState(() => _draftChoices = {
                      ...choices,
                      dim.id: dim.options[i].id,
                    }),
          ),
          const SizedBox(height: 8),
        ],
        // The instruction the choices compose into — SHOWN, not hidden,
        // because it is exactly what gets saved and what the model reads.
        const SizedBox(height: 4),
        KitSunkenNote(previewText),
        if (_error != null) ...[
          const SizedBox(height: 6),
          KitFailureInline(_error!),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KitButton.primary(_busy ? 'Saving…' : 'Save style',
                onPressed: (_busy || !dirty) ? null : () => _put(composed)),
            if (_draftChoices != null)
              KitButton.ghost('Cancel', onPressed: _busy ? null : _clearEdits),
            KitSettingLink('Fine-tune by hand', onTap: () {
              // Switching mode writes nothing.
              _textCtrl.text = composed ?? effectiveText;
              setState(() {
                _draftText = _textCtrl.text;
                _modeOverride = 'custom';
              });
            }),
          ],
        ),
      ],
    );
  }

  Widget _customMode(Map<String, String>? storedChoices, String? storedPrompt) {
    final custom = storedPrompt != null;
    final effectiveText = storedPrompt ?? defaultSummaryPrompt;
    if (_draftText == null && _textCtrl.text != effectiveText) {
      _textCtrl.text = effectiveText;
    }
    final shownText = _draftText ?? effectiveText;
    final textDirty =
        _draftText != null && _draftText!.trim() != effectiveText;
    final sendable = sendablePrompt(shownText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        KitTextField(
          controller: _textCtrl,
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => setState(() => _draftText = v),
        ),
        const SizedBox(height: 6),
        KitRowNote(
          '${custom ? 'Custom style in effect.' : 'Using the default summary style.'}'
          ' Up to $summaryPromptMaxChars characters.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          KitFailureInline(_error!),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KitButton.primary(_busy ? 'Saving…' : 'Save style',
                onPressed: (_busy || !textDirty || sendable == null)
                    ? null
                    : () => _put(sendable)),
            if (textDirty)
              KitButton.ghost('Cancel', onPressed: _busy ? null : _clearEdits),
            // Reset sends null — there is no "empty prompt" state to offer.
            if (custom)
              KitButton.ghost('Reset to default',
                  onPressed: _busy ? null : () => _put(null)),
            KitSettingLink('Use simple controls', onTap: () {
              // Adopt matching positions when the text is (or reverts to) a
              // composed shape; otherwise start from the stored positions or
              // the defaults. Nothing is written by switching modes.
              final parsed = parsePrompt(shownText.trim());
              setState(() {
                _draftChoices = parsed ?? storedChoices ?? defaultChoices;
                _draftText = null;
                _modeOverride = 'simple';
              });
            }),
          ],
        ),
      ],
    );
  }
}
