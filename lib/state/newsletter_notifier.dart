import 'package:flutter/foundation.dart';
import '../models/newsletter.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

/// Newsletter history (INV-09: query by recency, never construct IDs) +
/// "send now" via `fn_request_newsletter`. See spec/screens/letters.md.
class NewsletterNotifier extends ChangeNotifier {
  List<Newsletter> _history = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;

  List<Newsletter> get history => List.unmodifiable(_history);
  Newsletter? get latest => _history.isEmpty ? null : _history.first;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;

  Future<void> load({int limit = 30}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _history = await FirestoreService.instance.listNewsletters(limit: limit);
    } catch (_) {
      _error = 'Could not load newsletters.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// "Send now" — 60s cooldown against double-taps is enforced server-side;
  /// the result appears via the history query, never polled.
  Future<String?> requestNewsletter() async {
    _isSending = true;
    notifyListeners();
    try {
      await ApiService.instance.post('/fn_request_newsletter', data: const {});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to request newsletter. Please try again.';
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}
