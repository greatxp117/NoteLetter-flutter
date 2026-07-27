import 'document.dart' show tsMs;

/// `/users/{uid}/notification_channels/{id}` (contract 2.5.0 ADR-014; push type
/// 2.6.0 ADR-015). Subscribed, function-mediated writes. Timestamps → epoch ms
/// at the read boundary (INV-06).
class NotificationChannel {
  final String id;
  final String type; // email | onscreen | push
  final String? label;
  final List<String> levels; // subset of error|warning|success|info
  final String? destination; // email recipient; null for onscreen/push
  final bool enabled;
  final int? createdAt;
  final int? updatedAt;

  const NotificationChannel({
    required this.id,
    required this.type,
    this.label,
    this.levels = const [],
    this.destination,
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
  });

  factory NotificationChannel.fromJson(String id, Map<String, dynamic> d) =>
      NotificationChannel(
        id: id,
        type: d['type'] as String? ?? '',
        label: d['label'] as String?,
        levels: (d['levels'] as List?)?.map((e) => e as String).toList() ??
            const [],
        destination: d['destination'] as String?,
        enabled: d['enabled'] as bool? ?? true,
        createdAt: tsMs(d['created_at']),
        updatedAt: tsMs(d['updated_at']),
      );
}
