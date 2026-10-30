// The harness Letters' tests share (F-144, screens/letters.md §Composition,
// direction D): the REAL newsletter and readings-letter notifiers over a
// FirestoreService double, and a settings notifier that answers — and writes —
// what the test says. Not a test file itself.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/scripture_newsletter_settings.dart';
import 'package:flutter_app/pages/letters_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/scripture_letter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// Every read Letters makes, answered by the test. [hangLetters]: the archive
/// read never answers; [failLetters]: it is refused. [readings] null: the
/// readings-letter settings read never answers.
class LettersReads extends FirestoreService {
  LettersReads({
    this.letters = const [],
    this.pinned = const [],
    this.readings = const ScriptureNewsletterSettings(),
    this.hangLetters = false,
    this.failLetters = false,
    this.failReadings = false,
  }) : super.stub();

  final List<Newsletter> letters;
  final List<Document> pinned;
  final ScriptureNewsletterSettings? readings;
  final bool hangLetters;
  final bool failLetters;
  final bool failReadings;

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async {
    if (hangLetters) return Completer<List<Newsletter>>().future;
    if (failLetters) throw StateError('permission-denied');
    return letters.take(limit).toList();
  }

  @override
  Stream<List<Document>> subscribePinnedDocuments() => Stream.value(pinned);

  @override
  Future<ScriptureNewsletterSettings?> getScriptureNewsletterSettings() async {
    if (failReadings) throw StateError('permission-denied');
    if (readings == null) {
      return Completer<ScriptureNewsletterSettings?>().future;
    }
    return readings;
  }
}

/// The settings document as the test says it is ([value] null is a read
/// still out). [onDelivery] answers the delivery switch's write — the test
/// holds it open or refuses it; on success the stored document moves.
class LettersSettings extends SettingsNotifier {
  LettersSettings(this.value, {this.onDelivery});
  NewsletterSettings? value;
  final Future<String?> Function(bool enabled)? onDelivery;
  final List<bool> deliveryWrites = [];

  @override
  Future<void> loadAll() async {}

  @override
  NewsletterSettings? get newsletter => value;

  @override
  String? get error => null;

  @override
  Future<String?> setScheduledDelivery({
    required bool enabled,
    required String deliveryTime,
    required String timezone,
  }) async {
    deliveryWrites.add(enabled);
    final err = await (onDelivery?.call(enabled) ?? Future.value(null));
    if (err == null) {
      final v = value!;
      value = NewsletterSettings(
        enabled: enabled,
        emailAddress: v.emailAddress,
        deliveryTime: deliveryTime,
        timezone: timezone,
        frequency: v.frequency,
        itemsPerNewsletter: v.itemsPerNewsletter,
      );
      lastActivation = enabled
          ? {
              'activationSend': {'queued': true},
            }
          : null;
      notifyListeners();
    }
    return err;
  }
}

/// A send whose answer the test decides: null is queued, a string refused.
class LettersSender extends NewsletterNotifier {
  LettersSender({this.answer});
  final Future<String?> Function()? answer;
  int sends = 0;

  @override
  Future<String?> requestNewsletter() async {
    sends++;
    return answer == null ? null : await answer!();
  }
}

Newsletter lettersLetter(String id, Map<String, dynamic> json) =>
    Newsletter.fromJson(id, {'user_id': 'u1', 'status': 'sent', ...json});

/// Pumps Letters under the providers the app holds it under, at [size], in
/// [brightness], then a bounded run of frames (a skeleton's shimmer never
/// settles).
Future<NewsletterNotifier> pumpLetters(
  WidgetTester tester,
  LettersReads reads, {
  SettingsNotifier? settings,
  NewsletterNotifier? letters,
  Size size = const Size(1280, 2400),
  Brightness brightness = Brightness.light,
  String? accountEmail = 'reader@example.com',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = reads;
  addTearDown(FirestoreService.resetInstance);
  final notifier = letters ?? NewsletterNotifier();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NewsletterNotifier>.value(value: notifier),
        ChangeNotifierProvider<SettingsNotifier>(
          create: (_) => settings ?? LettersSettings(null),
        ),
        ChangeNotifierProvider<ScriptureLetterNotifier>(
          create: (_) => ScriptureLetterNotifier(),
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: LettersPage(accountEmail: () => accountEmail)),
      ),
    ),
  );
  await lettersFrames(tester);
  return notifier;
}

/// A bounded run of frames — never `pumpAndSettle` over a live animation.
Future<void> lettersFrames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The bundled faces: a width question is about the real labels, and the test
/// font (Ahem) draws every glyph a full em wide.
Future<void> lettersFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
