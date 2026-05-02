import 'package:flutter/foundation.dart';
import '../models/activity_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ActivityNotifier extends ChangeNotifier {
  List<ActivityItem> _items = [];
  bool _isLoading = false;
  String? _error;

  List<ActivityItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ActivityItem> get documents =>
      _items.where((i) => i.kind == 'document').toList();

  Future<void> load({int limit = 50}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.instance
          .get('/fn_list_activity', queryParameters: {'limit': limit});

      final rawList = data['items'] as List? ?? [];
      _items = rawList
          .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load activity. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();
}
