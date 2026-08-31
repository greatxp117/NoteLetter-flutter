/// The readings letter (contract 2.24.0 ADR-029; 2.26.0 ADR-030).
///
/// A second, **opt-in** letter that follows the day's lectionary readings and
/// searches the reader's own library for passages against them.
///
/// Three rules this surface exists to keep, each of which has bitten before:
///
///   * **No send action.** `fn_build_scripture_newsletter` is an OIDC-only
///     worker with no `fn_request_*` counterpart, so a "send now" button here
///     would be wired to nothing — the 1.5.1 defect exactly.
///   * The letter list filters `kind != "scripture"`, **never**
///     `kind == "daily"` — the field is absent on every pre-2.24.0 record.
///   * The calendar is **shown, not chosen**: `roman` is the only one the
///     shipped table answers completely.
library;

import 'package:flutter/material.dart';
import '../../models/newsletter.dart';
import '../../models/scripture_newsletter_settings.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../state/schedule.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import '../../theme/app_radius.dart';

class ReadingsLetterPanel extends StatefulWidget {
  const ReadingsLetterPanel({super.key});

  @override
  State<ReadingsLetterPanel> createState() => _ReadingsLetterPanelState();
}

class _ReadingsLetterPanelState extends State<ReadingsLetterPanel> {
  ScriptureNewsletterSettings? _settings;
  List<Newsletter> _letters = const [];
  bool _loading = true;
  /// §14 (ADR-070). Without this the catch set `_loading = false` and nothing
  /// else, so a failed read rendered `const ScriptureNewsletterSettings()` —
  /// the DEFAULTS — as if they were the reader's own: a card stating the
  /// readings letter is off, to a reader who has it on.
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.instance.getScriptureNewsletterSettings();
      final letters =
          await FirestoreService.instance.listScriptureNewsletters();
      if (!mounted) return;
      setState(() {
        _settings = ScriptureNewsletterSettings.fromJson(
            (res['settings'] as Map?)?.cast<String, dynamic>() ?? res);
        _letters = letters;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _save(ScriptureNewsletterSettings next) async {
    setState(() => _saving = true);
    try {
      // The write happens BEFORE the switch moves (ADR-022) — an optimistic
      // toggle that later fails leaves the reader believing a letter is
      // coming when none is.
      await Api.instance.updateScriptureNewsletterSettings(next.toJson());
      if (!mounted) return;
      setState(() => _settings = next);
      AppToast.show(
          context,
          next.enabled
              ? 'The readings letter is on.'
              : 'Paused. Your settings are kept.',
          type: ToastType.success);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not save that.', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    if (_loading) return const SizedBox.shrink();
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: KitFailureBlock(
          sentence: 'Your readings letter settings could not be read.',
          detail: _error!,
          onRetry: _load,
        ),
      );
    }
    final s = _settings ?? const ScriptureNewsletterSettings();

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The readings letter',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Each day\'s lectionary readings, with passages from your own '
            'library that speak to them.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.enabled,
            onChanged: _saving
                ? null
                : (v) => _save(s.copyWith(
                    enabled: v,
                    // A client sending deliveryTime sends timezone in the
                    // same call (2.29.0).
                    timezone: s.timezone.isEmpty ? deviceTimezone() : s.timezone)),
            title: const Text('Send me the readings letter'),
          ),
          if (s.enabled) ...[
            Text(
              scheduleSentence(
                enabled: s.enabled,
                deliveryTime: s.deliveryTime,
                timezone: s.timezone,
                frequency: s.frequency,
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 2),
            // SHOWN, not chosen: roman is the only calendar the shipped table
            // answers completely (rcl is Sundays by nature; anglican was
            // deleted at 2.25.1 for being generated from the date).
            Text('Following the ${s.calendar} calendar.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          // Deliberately NO send action here.
          if (_letters.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Recent', style: theme.textTheme.labelLarge),
            for (final n in _letters.take(5)) _row(theme, muted, n),
          ],
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, Color muted, Newsletter n) {
    // passages_sent/found are stored AS SENT, so "5 of 23" stays honest even
    // as the library grows underneath it.
    final counts = (n.passagesSent != null && n.passagesFound != null)
        ? '${n.passagesSent} of ${n.passagesFound} passages'
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(n.liturgicalDay ?? 'Readings',
                style: theme.textTheme.bodyMedium),
          ),
          if (counts != null)
            Text(counts,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          // 2.26.0 — where the verse text came from. `bible_on_shelf` keeps
          // its 2.24.0 meaning (the reader owns an edition) and must NOT be
          // read as "we had no verse text".
          if (n.verseSource == 'system' && n.verseEdition != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(n.verseEdition!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
        ],
      ),
    );
  }
}
