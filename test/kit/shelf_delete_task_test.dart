// library.md §Deleting a shelf (4.101.0, ADR-136): the delete is a background
// task. The confirmation holds until fn_request_task answers, sends
// {kind: shelf_delete, tagId, reshelve}, and a refusal stays in the panel; a
// `deleting` shelf is gone from the tags stream the moment it is marked.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags/shelf_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

class _Capture implements HttpClientAdapter {
  final bodies = <String, dynamic>{};
  int status = 202;
  Map<String, dynamic> answer = {'taskId': 'tsk-1', 'status': 'queued'};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? req,
      Future<void>? cancel) async {
    final bytes = <int>[];
    if (req != null) await for (final p in req) {bytes.addAll(p);}
    bodies[o.uri.path] = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    return ResponseBody.fromString(jsonEncode(answer), status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

class _Tags extends TagsNotifier {
  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  List<Tag> get tags => [
        Tag.fromJson('s1', {'user_id': 'u1', 'title': 'Psalms'}),
        Tag.fromJson('s2', {'user_id': 'u1', 'title': 'Hymns'}),
      ];
}

class _Docs extends DocumentsNotifier {
  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  List<Document> get documents => complete;
  _Docs({this.volumes = const []});
  final List<Document> volumes;

  @override
  // With a volume the header carries a third action (Find sources for this
  // shelf), which overflowed the 768 column by 96px in the test font (Ahem)
  // while the actions were a Row (2026-10-02). They wrap now, so the case with
  // a volume — the one that sends `reshelve: true` — is driven here too.
  List<Document> get complete => volumes;
}

Future<_Capture> _delete(WidgetTester tester,
    {int status = 202, List<Document> volumes = const []}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final capture = _Capture()..status = status;
  if (status >= 400) {
    capture.answer = {'error': 'This shelf is already being deleted.', 'error_code': 'SHELF_DELETING'};
  }
  ApiService.instance.tokenProvider = () async => 'test-token';
  ApiService.instance.httpClientAdapter = capture;
  addTearDown(ApiService.instance.resetTestSeams);
  final router = GoRouter(initialLocation: '/shelves/s1', routes: [
    GoRoute(path: '/shelves', builder: (_, _) => const Text('all shelves')),
    GoRoute(
        path: '/shelves/:id',
        builder: (_, s) => Scaffold(body: ShelfPage(shelfId: s.pathParameters['id']!))),
  ]);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<TagsNotifier>(create: (_) => _Tags()),
      ChangeNotifierProvider<DocumentsNotifier>(
          create: (_) => _Docs(volumes: volumes)),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  ));
  await tester.pump();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete shelf'));
  await tester.pumpAndSettle();
  // The panel's own confirm (the settings control is the first match).
  await tester.tap(find.text('Delete shelf').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  return capture;
}

void main() {
  testWidgets('the delete is fn_request_task, and the reader goes back to the index',
      (tester) async {
    final c = await _delete(tester);
    expect(c.bodies['/fn_request_task'],
        {'kind': 'shelf_delete', 'tagId': 's1', 'reshelve': false});
    expect(c.bodies.containsKey('/fn_delete_tag'), isFalse);
    expect(find.text('all shelves'), findsOneWidget);
  });

  testWidgets('with a volume the header wraps, and the delete offers the re-shelve',
      (tester) async {
    final c = await _delete(tester, volumes: [
      Document(
          id: 'd1',
          userId: 'u1',
          title: 'Psalm 23',
          type: 'text',
          status: DocumentStatus.complete,
          tagIds: const ['s1']),
    ]);
    // The overflow was a layout exception; a wrapped header raises none.
    expect(tester.takeException(), isNull);
    expect(c.bodies['/fn_request_task'],
        {'kind': 'shelf_delete', 'tagId': 's1', 'reshelve': true});
  });

  testWidgets('a refusal answers inside the panel, and the shelf stays', (tester) async {
    await _delete(tester, status: 409);
    expect(find.text('This shelf is already being deleted.'), findsOneWidget);
    expect(find.text('all shelves'), findsNothing);
  });

  test('a deleting shelf is filtered from the tags stream', () {
    expect(isDeletingTag({'status': 'deleting'}), isTrue);
    expect(isDeletingTag({'title': 'x'}), isFalse);
  });
}
