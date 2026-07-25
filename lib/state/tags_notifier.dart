import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/tag.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

/// Tags surface — the live tags subscription (INV-02) plus the function-mediated
/// mutations (INV-04; tags are written only through `fn_*`).
class TagsNotifier extends ChangeNotifier {
  List<Tag> _tags = [];
  StreamSubscription<List<Tag>>? _sub;
  bool _loading = true;

  List<Tag> get tags => List.unmodifiable(_tags);
  bool get loading => _loading;

  void start() {
    _sub ??= FirestoreService.instance.subscribeTags().listen((list) {
      _tags = list;
      _loading = false;
      notifyListeners();
    });
  }

  Future<String?> createTag(String title,
      {String? description, String? color}) async {
    try {
      await ApiService.instance.post('/fn_create_tag', data: {
        'title': title,
        if (description != null) 'description': description,
        if (color != null) 'color': color,
      });
      return null; // the subscription reflects the new tag
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not create the tag.';
    }
  }

  Future<String?> updateTag(String tagId,
      {String? title, String? description, String? color}) async {
    try {
      await ApiService.instance.post('/fn_update_tag', data: {
        'tagId': tagId,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (color != null) 'color': color,
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update the tag.';
    }
  }

  Future<String?> deleteTag(String tagId) async {
    try {
      await ApiService.instance.post('/fn_delete_tag', data: {'tagId': tagId});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not delete the tag.';
    }
  }

  /// LLM tag suggestions from the user's purpose text (5–8). Returns the raw
  /// suggestion maps for a review sheet, or null on failure.
  Future<List<Map<String, dynamic>>?> suggestTags(String purposeText) async {
    try {
      final data = await ApiService.instance
          .post('/fn_suggest_tags', data: {'purposeText': purposeText});
      return ((data['tags'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Persist accepted suggestions in one batch.
  Future<String?> approveTags(List<Map<String, dynamic>> tags) async {
    try {
      await ApiService.instance.post('/fn_approve_tags', data: {'tags': tags});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not save the tags.';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
