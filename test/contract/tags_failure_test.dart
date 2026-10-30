/// INV-24 (ADR-071) for the shelves read, as `documents_failure_test.dart`
/// holds it for the documents read: a refused `tags` subscription is an
/// ERROR, never an empty list, and the next `start` reads again.
///
/// F-141's device run found the second half missing. `TagsNotifier.start` is
/// idempotent on its subscription, and the error path kept it — so a shelves
/// read refused once (the first read after an account switch is answered as
/// the previous user) stayed refused for the life of the app, and Home in
/// direction D, which needs the shelves read to call the library measured,
/// drew a failed library that no screen could clear.
///
/// The REAL notifier runs, against a stream that fails on command.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/tags_notifier.dart';

class _Tags extends FirestoreService {
  _Tags() : super.stub();

  final List<StreamController<List<Tag>>> opened = [];

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Tag>> subscribeTags() {
    final c = StreamController<List<Tag>>();
    opened.add(c);
    return c.stream;
  }
}

void main() {
  late _Tags service;
  setUp(() => FirestoreService.instance = service = _Tags());
  tearDown(FirestoreService.resetInstance);

  test('a refused read is an error, and the next start reads again', () async {
    final tags = TagsNotifier()..start();
    expect(service.opened, hasLength(1));
    expect(tags.loading, isTrue);

    service.opened.single.addError(StateError('permission-denied'));
    await pumpEventQueue();
    expect(tags.loading, isFalse);
    expect(tags.error, isNotNull, reason: 'a refused read is not "no shelves"');

    tags.start();
    expect(service.opened, hasLength(2),
        reason: 'the failed subscription was kept, so start could never '
            'read again');
    service.opened.last.add(const [
      Tag(id: 's1', userId: 'u1', title: 'Cooking'),
    ]);
    await pumpEventQueue();
    expect(tags.error, isNull);
    expect(tags.tags.single.title, 'Cooking');
    tags.dispose();
  });

  test('start is idempotent while the read is live', () async {
    final tags = TagsNotifier()..start();
    tags.start();
    expect(service.opened, hasLength(1),
        reason: 'a second screen asking for the shelves shares the read');
    tags.dispose();
  });
}
