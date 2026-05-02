import 'package:flutter/foundation.dart';
import '../models/search_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class SearchNotifier extends ChangeNotifier {
  List<SearchResult> _results = [];
  bool _isLoading = false;
  String? _error;
  String _query = '';

  List<SearchResult> get results => List.unmodifiable(_results);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get query => _query;
  bool get hasResults => _results.isNotEmpty;

  Future<void> search(
    String query, {
    List<String>? sourceTypes,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return;
    }

    _query = trimmed;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.instance.post('/fn_search_notes', data: {
        'query': trimmed,
        if (sourceTypes != null) 'sourceTypes': sourceTypes,
        'limit': limit,
      });

      final rawList = data['results'] as List? ?? [];
      _results = rawList
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
      _error = null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Search failed. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _results = [];
    _query = '';
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
