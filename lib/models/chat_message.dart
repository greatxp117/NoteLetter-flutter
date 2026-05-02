class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final List<String> citations;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.citations = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
