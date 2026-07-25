import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chunk.dart';
import '../models/document.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';

/// Reader — one-shot doc + chunks (`chunk_index` asc), fires `logReadEvent`
/// on open (INV-03). See spec/screens/reader.md.
class ReaderPage extends StatefulWidget {
  final String docId;

  const ReaderPage({super.key, required this.docId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _loading = true;
  String? _error;
  Document? _document;
  List<Chunk> _chunks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result =
          await FirestoreService.instance.getReaderDocument(widget.docId);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = 'Document not found.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _document = result.$1;
        _chunks = result.$2;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this document.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/library'),
        ),
        title: Text(
          _document?.title ?? 'Reader',
          style: GoogleFonts.sourceSerif4(
              fontSize: 18, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_document?.sourceUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(_document!.sourceUrl!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted)),
                          ),
                        if (_document?.summary != null &&
                            _document!.summary!.isNotEmpty) ...[
                          Text('Summary',
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(_document!.summary!,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontStyle: FontStyle.italic)),
                          const SizedBox(height: 24),
                        ],
                        // Chunks in reading order — plain text render (no
                        // HTML renderer dependency yet; `chunk.html` carries
                        // the rich markup, assembled client-side since 1.1.0).
                        ..._chunks.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                c.text,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(height: 1.6),
                              ),
                            )),
                        if (_chunks.isEmpty)
                          Text('No content indexed yet.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: muted)),
                      ],
                    ),
                  ),
                ),
    );
  }
}
