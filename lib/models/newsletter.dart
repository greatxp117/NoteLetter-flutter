import 'document.dart' show tsMs;

/// `/newsletters/{newsletterId}` — read-only; never construct IDs, query by
/// `generated_at desc` (INV-09).
class Newsletter {
  final String id;
  final String userId;
  final int? generatedAt;
  final String html;
  final String trigger;
  final String status;

  const Newsletter({
    required this.id,
    required this.userId,
    this.generatedAt,
    required this.html,
    required this.trigger,
    required this.status,
  });

  factory Newsletter.fromJson(String id, Map<String, dynamic> json) {
    return Newsletter(
      id: id,
      userId: json['user_id'] as String? ?? '',
      generatedAt: tsMs(json['generated_at']),
      html: json['html'] as String? ?? '',
      trigger: json['trigger'] as String? ?? 'scheduled',
      status: json['status'] as String? ?? '',
    );
  }
}
