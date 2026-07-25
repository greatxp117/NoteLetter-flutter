import 'document.dart' show tsMs;

/// `/newsletters/{newsletterId}` — read-only; never construct IDs, query by
/// `generated_at desc` (INV-09).
class Newsletter {
  final String id;
  final String userId;
  final int? generatedAt;
  final String html;
  final String trigger;

  /// `generating | sent | error | empty` (2.2.0, ADR-011) — vocabulary is
  /// OPEN: an unknown status renders as informational, never as a failure.
  final String status;

  /// Client-visible failure/skip reason; set on `error` and `empty`.
  final String? errorMessage;

  const Newsletter({
    required this.id,
    required this.userId,
    this.generatedAt,
    required this.html,
    required this.trigger,
    required this.status,
    this.errorMessage,
  });

  factory Newsletter.fromJson(String id, Map<String, dynamic> json) {
    return Newsletter(
      id: id,
      userId: json['user_id'] as String? ?? '',
      generatedAt: tsMs(json['generated_at']),
      html: json['html'] as String? ?? '',
      trigger: json['trigger'] as String? ?? 'scheduled',
      status: json['status'] as String? ?? '',
      errorMessage: json['error_message'] as String?,
    );
  }

  /// A row is a readable letter only when it was actually rendered and sent.
  /// `empty`/`error` (and any future non-`sent` status) carry no `html` to
  /// preview — they are informational history rows.
  bool get isReadable => status == 'sent' && html.isNotEmpty;
}
