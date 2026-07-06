import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/newsletter.dart';
import '../state/newsletter_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

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
                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor:
                                        primary.withValues(alpha: 0.08),
                                    title: Text(_formatDate(n.generatedAt),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      n.trigger == 'manual'
                                          ? 'Manual send'
                                          : 'Scheduled',
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
}
