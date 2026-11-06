import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';

/// A tags read a test delivers by hand, and counts being asked for: kit §20.3's
/// rule is about what the read has and has not delivered yet.
class LiveTags extends TagsNotifier {
  LiveTags([this.shelves = const []]);
  List<Tag> shelves;
  int starts = 0;

  @override
  void start() => starts++;

  @override
  List<Tag> get tags => shelves;

  void deliver(List<Tag> next) {
    shelves = next;
    notifyListeners();
  }
}

/// The documents subscription, never opened: the library holds nothing complete.
class QuietDocs extends DocumentsNotifier {
  int starts = 0;

  @override
  void start() => starts++;
}

Tag shelf(String id, String title, {String? parent, int count = 3}) => Tag(
      id: id,
      userId: 'u1',
      title: title,
      color: 'teal-500',
      documentCount: count,
      parentTagId: parent,
    );
