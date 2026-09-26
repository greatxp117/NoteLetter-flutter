/// F-53, **Draw from** (web LetterSettings): the shelves the daily letter
/// leans on, saved as `topicFilters` — shelf TITLES, not ids — in the same
/// `fn_newsletter_settings` PUT as the rest of the form. This client had no
/// such control, so a reader here could neither set it nor see it.
///
/// The page itself reads the signed-in account in `build`, which no test here
/// can supply, so the group and its payload are extracted and driven directly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/letter_settings_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Recorder implements HttpClientAdapter {
  final List<RequestOptions> sent = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString(jsonEncode({'ok': true}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Tag _shelf(String id, String title, String color) =>
    Tag.fromJson(id, {'user_id': 'u1', 'title': title, 'color': color});

final _shelves = [
  _shelf('s1', 'Pasta', 'sage-500'),
  _shelf('s2', 'Stories', 'plum-600'),
];

void main() {
  tearDown(() => ApiService.instance.resetTestSeams());

  test('the stored key is read', () {
    expect(
        NewsletterSettings.fromJson({
          'topicFilters': ['Pasta']
        }).topicFilters,
        ['Pasta']);
    expect(NewsletterSettings.fromJson(const {}).topicFilters, isEmpty);
  });

  test('the payload is titles in shelf order; a vanished shelf is dropped', () {
    expect(topicFiltersFor(_shelves, {'Stories', 'A shelf since deleted', 'Pasta'}),
        ['Pasta', 'Stories']);
    expect(topicFiltersFor(_shelves, {}), isEmpty);
  });

  testWidgets('the group ticks the stored titles and counts what is in play',
      (tester) async {
    final selected = {'Pasta', 'A shelf since deleted'};
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => LetterDrawFrom(
            shelves: _shelves,
            selected: selected,
            onChanged: (t, v) =>
                setState(() => v ? selected.add(t) : selected.remove(t)),
          ),
        ),
      ),
    ));
    expect(find.byType(KitSourceToggle), findsNWidgets(2));
    expect(find.textContaining('1 shelves'), findsOneWidget,
        reason: 'the deleted shelf is not counted');
    bool on(String title) => tester
        .widget<KitSourceToggle>(find.widgetWithText(KitSourceToggle, title))
        .value;
    expect(on('Pasta'), isTrue);
    expect(on('Stories'), isFalse);

    await tester.tap(find.descendant(
        of: find.widgetWithText(KitSourceToggle, 'Stories'),
        matching: find.byType(KitSwitch)));
    await tester.pump();
    expect(on('Stories'), isTrue);
    expect(find.textContaining('2 shelves'), findsOneWidget);

    for (final t in ['Pasta', 'Stories']) {
      await tester.tap(find.descendant(
          of: find.widgetWithText(KitSourceToggle, t),
          matching: find.byType(KitSwitch)));
      await tester.pump();
    }
    expect(find.textContaining('all shelves'), findsOneWidget);
  });

  test('the save carries topicFilters in the same PUT', () async {
    ApiService.instance.tokenProvider = () async => 'test-token';
    final rec = _Recorder();
    ApiService.instance.httpClientAdapter = rec;
    await SettingsNotifier().saveLetterSettings(
      emailAddress: '',
      frequency: 'daily',
      deliveryTime: '08:00',
      timezone: 'America/Chicago',
      purposeText: '',
      itemsPerNewsletter: 3,
      excludeRecentDays: 7,
      topicFilters: topicFiltersFor(_shelves, {'Stories'}),
    );
    final put = rec.sent.single;
    expect(put.path, endsWith('/fn_newsletter_settings'));
    expect(put.method, 'PUT');
    expect((put.data as Map)['topicFilters'], ['Stories']);
  });
}
