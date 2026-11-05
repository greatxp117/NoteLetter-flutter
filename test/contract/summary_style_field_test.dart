// The summary-style field (Settings › Summaries, *Fine-tune by hand*) is kit
// §6.9's sentence field (5.63.x; web `.ss-input.sf-desc`, TODO L2437's web
// half): the sans sentence face, as Letter settings' Your librarian is, and
// held while its save is out. It drew the mono data face, the field's default.
//
// Mutants run against it (each red): the face back to the default (mono); the
// field left live while Save's request is out.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/settings/summaries_section.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Held implements HttpClientAdapter {
  final open = Completer<void>();
  int sent = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent++;
    await open.future;
    return ResponseBody.fromString(jsonEncode({}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Stored extends FirestoreService {
  _Stored(this.prompt) : super.stub();
  final String? prompt;
  @override
  Stream<String?> subscribeSummarySettings() => Stream.value(prompt);
}

const _custom = 'Summarise like a field naturalist: what was seen, where, and '
    'what it suggests.';

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  Future<void> pump(WidgetTester tester) async {
    FirestoreService.instance = _Stored(_custom);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
          body: SingleChildScrollView(child: SummariesSection())),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final field = find.byKey(const ValueKey('summary-style-field'));
    if (field.evaluate().isEmpty) {
      final fine = find.widgetWithText(KitSettingLink, 'Fine-tune by hand');
      await tester.ensureVisible(fine);
      await tester.tap(fine);
      await tester.pump();
    }
  }

  KitTextField field(WidgetTester tester) => tester.widget<KitTextField>(
      find.byKey(const ValueKey('summary-style-field')));

  testWidgets('a style is a sentence: the sans face, never the data face',
      (tester) async {
    await pump(tester);
    expect(field(tester).face, KitFieldFace.sans);
  });

  testWidgets('held while its save is out', (tester) async {
    final held = _Held();
    ApiService.instance.httpClientAdapter = held;
    await pump(tester);
    expect(field(tester).enabled, isTrue);
    await tester.enterText(
        find.byKey(const ValueKey('summary-style-field')), 'Short and plain.');
    await tester.pump();
    final save = find.widgetWithText(KitButton, 'Save style');
    await tester.ensureVisible(save);
    await tester.tap(save);
    for (var i = 0; i < 5 && held.sent == 0; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(held.sent, 1);
    expect(field(tester).enabled, isFalse);
    held.open.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(field(tester).enabled, isTrue);
  });
}
