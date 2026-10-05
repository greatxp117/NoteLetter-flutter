// library.md §Creating a shelf (4.102.0, ADR-136; QUEUE F-72 f): the Shelves
// index's New shelf card is the rail sheet's form, and it ends the same way.
// The new shelf opens at once; the fill, when asked for, is a background task
// (`fn_request_task {kind: shelf_backfill}`) said by a local toast, and its
// proposal waits in For your review. Until 2026-10-05 this card alone still
// opened the live in-sheet review over `fn_suggest_shelf_backfill` — found by
// comparing the re-shot shelves pair, not by any test.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

class _Capture implements HttpClientAdapter {
  final bodies = <String, dynamic>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? req,
      Future<void>? cancel) async {
    final bytes = <int>[];
    if (req != null) await for (final p in req) {bytes.addAll(p);}
    bodies[o.uri.path] = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    final answer = o.uri.path == '/fn_create_tag'
        ? {'tagId': 't9'}
        : {'taskId': 'tsk-1', 'status': 'queued'};
    return ResponseBody.fromString(jsonEncode(answer), 200,
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
  List<Tag> get tags =>
      [Tag.fromJson('s1', {'user_id': 'u1', 'title': 'Psalms'})];
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
  // One complete source, so the form offers the fill.
  @override
  List<Document> get complete => [
        Document.fromJson('d1', {
          'user_id': 'u1',
          'title': 'Sourdough notes',
          'type': 'pdf',
          'status': 'complete',
        }),
      ];
}

Future<(_Capture, GoRouter)> _create(WidgetTester tester,
    {required bool fill}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final capture = _Capture();
  ApiService.instance.tokenProvider = () async => 'test-token';
  ApiService.instance.httpClientAdapter = capture;
  addTearDown(ApiService.instance.resetTestSeams);
  final router = GoRouter(initialLocation: '/shelves', routes: [
    GoRoute(
        path: '/shelves',
        builder: (_, _) => const Scaffold(body: ShelvesPage())),
    GoRoute(
        path: '/shelves/:id',
        builder: (_, s) =>
            Scaffold(body: Text('shelf ${s.pathParameters['id']}'))),
  ]);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<TagsNotifier>(create: (_) => _Tags()),
      ChangeNotifierProvider<DocumentsNotifier>(create: (_) => _Docs()),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  ));
  await tester.pump();
  await tester.tap(find.text('New shelf'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'Bread');
  await tester.pump();
  if (!fill) {
    await tester.tap(find.text('Find sources that belong here'));
    await tester.pump();
  }
  await tester.tap(find.text('Create shelf'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  return (capture, router);
}

void main() {
  testWidgets('with the fill: the shelf opens and the fill is a background task',
      (tester) async {
    final (c, router) = await _create(tester, fill: true);
    expect(c.bodies['/fn_create_tag']?['title'], 'Bread');
    expect(c.bodies['/fn_request_task'],
        {'kind': 'shelf_backfill', 'tagId': 't9'});
    expect(c.bodies.containsKey('/fn_suggest_shelf_backfill'), isFalse,
        reason: 'the live in-sheet review was retired at 4.102.0');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/shelves/t9');
    expect(find.text('shelf t9'), findsOneWidget);
    expect(find.text('Fill Bread'), findsNothing);
    expect(find.textContaining('in the background'), findsOneWidget);
  });

  testWidgets('without it: the shelf opens and nothing else is asked',
      (tester) async {
    final (c, router) = await _create(tester, fill: false);
    expect(c.bodies.keys, ['/fn_create_tag']);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/shelves/t9');
    expect(find.textContaining('in the background'), findsNothing);
  });
}
