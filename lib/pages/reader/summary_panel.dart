import 'package:flutter/material.dart';
import '../../models/document.dart';
import 'reader_ui.dart';

/// Reader → Summary panel: `summary`, `key_points`, `themes` off the document.
/// `questions` is deprecated and NEVER rendered (ADR-008), even when present on
/// pre-1.5.0 docs. Per reader.md.
class SummaryPanel extends StatelessWidget {
  final Document doc;
  const SummaryPanel({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final hasSummary = (doc.summary?.isNotEmpty ?? false) ||
        doc.keyPoints.isNotEmpty ||
        doc.themes.isNotEmpty;

    if (!hasSummary) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ui.intro('Summary · what this source is about'),
          ui.empty(Icons.auto_awesome_outlined, 'No summary yet.',
              "This source hasn't been summarized."),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ui.eyebrow('Summary · what this source is about'),
        if (doc.summary?.isNotEmpty ?? false) ui.note(doc.summary!),
        const SizedBox(height: 20),
        if (doc.themes.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: doc.themes
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ui.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: ui.border),
                      ),
                      child: Text(t,
                          style: TextStyle(fontFamily: 'Geist', 
                              fontSize: 12, color: ui.muted)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        if (doc.keyPoints.isNotEmpty) ...[
          ui.eyebrow('Key points'),
          const SizedBox(height: 10),
          ...doc.keyPoints.map((kp) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                            color: ui.primary, shape: BoxShape.circle),
                      ),
                    ),
                    Expanded(
                      child: Text(kp,
                          style: TextStyle(fontFamily: 'Geist', 
                              fontSize: 15, height: 1.5, color: ui.fg)),
                    ),
                  ],
                ),
              )),
        ],
      ],
    );
  }
}
