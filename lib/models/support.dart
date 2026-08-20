import 'document.dart' show tsMs;

/// The support thread and its messages (contract 4.18.0, ADR-054;
/// `spec/data-model.md` §/support_threads, `spec/api/support.md` §Reads).
///
/// One thread per user, at the fixed path `/support_threads/{uid}` — a
/// document, never a query (INV-02). **An absent thread is a normal state**:
/// nobody has written to support yet. It maps to `null`, and the screen renders
/// its empty state; it is not an error and must never be surfaced as one.

/// Who wrote a message.
///
/// **Open vocabulary for reading** (`spec/api/support.md` §Reads): anything
/// that is not `user` renders as the other side, so a later `sender: "system"`
/// needs no breaking client change. This is deliberately not an enum with a
/// `system` case — the point is that an *unknown* value is already handled.
enum SupportSender {
  user,
  support;

  static SupportSender fromString(String? s) =>
      s == 'user' ? SupportSender.user : SupportSender.support;
}

class SupportThread {
  final String id;

  /// `user | support` — the side that wrote last.
  ///
  /// The "awaiting an answer" state is **derived from this**, never from a
  /// stored status field (`spec/screens/support.md` §States). A second field
  /// saying the same thing is a second field that can disagree.
  final SupportSender? lastSender;
  final int messageCount;
  final int unreadForUser;
  final int? createdAt;
  final int? lastMessageAt;

  const SupportThread({
    required this.id,
    this.lastSender,
    this.messageCount = 0,
    this.unreadForUser = 0,
    this.createdAt,
    this.lastMessageAt,
  });

  /// INV-06: every timestamp becomes epoch ms at the read boundary.
  factory SupportThread.fromJson(String id, Map<String, dynamic> json) =>
      SupportThread(
        id: id,
        lastSender: json['last_sender'] == null
            ? null
            : SupportSender.fromString(json['last_sender'] as String?),
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
        unreadForUser: (json['unread_for_user'] as num?)?.toInt() ?? 0,
        createdAt: tsMs(json['created_at']),
        lastMessageAt: tsMs(json['last_message_at']),
      );

  bool get awaitingAnswer => lastSender == SupportSender.user;
}

class SupportMessage {
  final String id;
  final SupportSender sender;
  final String body;

  /// The screen the user was on when they opened support. Free-form — a
  /// **client** route name the backend never interprets, so this client may add
  /// a screen without a contract change (`spec/api/support.md` §Validation).
  final String? route;
  final int? createdAt;

  const SupportMessage({
    required this.id,
    required this.sender,
    required this.body,
    this.route,
    this.createdAt,
  });

  factory SupportMessage.fromJson(String id, Map<String, dynamic> json) =>
      SupportMessage(
        id: id,
        sender: SupportSender.fromString(json['sender'] as String?),
        body: (json['body'] as String?) ?? '',
        route: json['route'] as String?,
        createdAt: tsMs(json['created_at']),
      );
}
