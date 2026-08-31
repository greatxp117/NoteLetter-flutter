import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/tag.dart';
import '../services/api.dart';
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
      await Api.instance.createTag(title, description: description, color: color);
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
      await Api.instance.updateTag(tagId, {
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
      await Api.instance.deleteTag(tagId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not delete the tag.';
    }
  }

  /// Persist accepted suggestions in one batch.
  Future<String?> approveTags(List<Map<String, dynamic>> tags) async {
    try {
      await Api.instance.approveTags(tags);
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
