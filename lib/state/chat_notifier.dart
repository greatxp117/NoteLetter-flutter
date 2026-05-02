import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/search_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ChatNotifier extends ChangeNotifier {
  final List<ChatMessage> _messages = [
    ChatMessage(
      id: '0',
      text:
          'Hello! Ask me anything about your knowledge base and I will find the most relevant insights from your uploaded documents.',
      isUser: false,
      citations: [],
    ),
  ];
  bool _isTyping = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isTyping => _isTyping;

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _messages.add(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: trimmed,
      isUser: true,
    ));
    _isTyping = true;
    notifyListeners();

    try {
      final data = await ApiService.instance.post('/fn_search_notes', data: {
        'query': trimmed,
        'limit': 5,
      });

      final rawList = data['results'] as List? ?? [];
      final results = rawList
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();

      _isTyping = false;

      if (results.isEmpty) {
        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text:
              'I did not find anything in your knowledge base matching that query. '
              'Try uploading more documents or rephrasing your question.',
          isUser: false,
          citations: [],
        ));
      } else {
        final topResult = results.first;
        final excerpt = topResult.chunk.text.length > 800
            ? '${topResult.chunk.text.substring(0, 800)}...'
            : topResult.chunk.text;

        final citations = results
            .map((r) => '${r.document.title} (${_typeLabel(r.document.type)})')
            .toList();

        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: excerpt,
          isUser: false,
          citations: citations,
        ));
      }
    } on UnauthorizedException {
      _isTyping = false;
      await AuthService.instance.signOut();
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Session expired. Please log in again.',
        isUser: false,
        citations: [],
      ));
    } on ApiException catch (e) {
      _isTyping = false;
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Error: ${e.message}',
        isUser: false,
        citations: [],
      ));
    } catch (_) {
      _isTyping = false;
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text:
            'Could not reach the knowledge base. Please check your connection and try again.',
        isUser: false,
        citations: [],
      ));
    } finally {
      notifyListeners();
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'pdf': return 'PDF';
      case 'youtube': return 'YouTube';
      case 'url': return 'Article';
      case 'docx': return 'Word';
      case 'image': return 'Image';
      default: return type;
    }
  }
}
