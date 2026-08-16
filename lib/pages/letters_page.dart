import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/newsletter.dart';
import '../state/newsletter_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../state/settings_notifier.dart';
import 'letters/pinned_sources.dart';

/// Letters — newsletter history (INV-09) + "send now". See
/// spec/screens/letters.md.
class LettersPage extends StatefulWidget {
  const LettersPage({super.key});

  @override
  State<LettersPage> createState() => _LettersPageState();
}

class _LettersPageState extends State<LettersPage> {
  Newsletter? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NewsletterNotifier>().load();
      // The pinned block reads `itemsPerNewsletter` from settings and never
      // defaults it, so the settings must actually be loaded for the "how many
      // arrive" sentence to appear at all.
      final settings = context.read<SettingsNotifier>();
      if (settings.newsletter == null) settings.loadAll();
    });
  }

  Future<void> _sendNow() async {
    final notifier = context.read<NewsletterNotifier>();
    final error = await notifier.requestNewsletter();
    if (!mounted) return;
    if (error != null) {
      AppToast.show(context, error, type: ToastType.error);
    } else {
      AppToast.show(context, 'Newsletter queued — it will appear here shortly.',
          type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer<NewsletterNotifier>(
      builder: (context, notifier, _) {
        final selected = _selected ?? notifier.latest;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // History list
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Letters',
                            style: GoogleFonts.sourceSerif4(
                                fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        // 2.33.0 — the pin's only surface outside the
                        // extension. Above "Send now" because it describes what
                        // the NEXT letter will carry.
                        PinnedSources(
                            settings: context.watch<SettingsNotifier>().newsletter),
                        FilledButton.icon(
                          onPressed: notifier.isSending ? null : _sendNow,
                          style: FilledButton.styleFrom(backgroundColor: primary),
                          icon: notifier.isSending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send, size: 16),
                          label: const Text('Send now'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: notifier.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : notifier.history.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No newsletters yet. Configure your preferences '
                                  'in Settings, or send one now.',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: muted),
                                ),
                              )
                            : ListView.builder(
                                itemCount: notifier.history.length,
                                itemBuilder: (context, i) {
                                  final n = notifier.history[i];
                                  final isSelected = n.id == selected?.id;
                                  final badge = _statusBadge(n.status);
                                  // empty/error rows carry no html to preview;
                                  // show their reason instead of the trigger.
                                  final sub = n.isReadable
                                      ? (n.trigger == 'manual'
                                          ? 'Manual send'
                                          : 'Scheduled')
                                      : (n.errorMessage ??
                                          (n.trigger == 'manual'
                                              ? 'Manual send'
                                              : 'Scheduled'));
                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor:
                                        primary.withValues(alpha: 0.08),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(_formatDate(n.generatedAt),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600)),
                                        ),
                                        if (badge != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: badge.color
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(badge.label,
                                                style: theme.textTheme.labelSmall
                                                    ?.copyWith(
                                                        color: badge.color,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      sub,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: muted),
                                    ),
                                    onTap: () => setState(() => _selected = n),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            VerticalDivider(
                width: 1,
                color: isDark ? AppColors.borderDark : AppColors.borderLight),
            // Rendered newsletter
            Expanded(
              child: selected == null
                  ? Center(
                      child: Text('Select a newsletter to view it.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted)),
                    )
                  : !selected.isReadable
                      // empty/error/generating: nothing was rendered — show the
                      // reason as an informational panel, not a broken preview.
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(48),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    selected.status == 'error'
                                        ? Icons.error_outline
                                        : Icons.mark_email_read_outlined,
                                    size: 32,
                                    color: muted),
                                const SizedBox(height: 12),
                                Text(_statusBadge(selected.status)?.label ??
                                    'No content',
                                    style: theme.textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(
                                  selected.errorMessage ??
                                      'This newsletter has no content to display.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: muted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
                          child: Html(data: selected.html),
                        ),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(int? ms) {
    if (ms == null) return 'Unknown date';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  /// Status → badge (contract 2.2.0, ADR-011). `sent` needs no badge; `empty`
  /// is informational ("Nothing new"), not a failure. Unknown statuses fall
  /// through to an informational badge — the vocabulary is open.
  _Badge? _statusBadge(String status) {
    switch (status) {
      case 'sent':
        return null;
      case 'error':
        return const _Badge('Failed', AppColors.critical);
      case 'empty':
        return const _Badge('Nothing new', AppColors.mutedForeground);
      case 'generating':
        return const _Badge('Sending…', AppColors.secondaryAccent);
      case '':
        return null;
      default:
        return _Badge(status, AppColors.mutedForeground);
    }
  }
}

class _Badge {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
}
