/// F-193 — a refused letter-settings read says web's words and §14.3's
/// sentence, never a constant (web `kit/d/LetterQuick.jsx:50`,
/// `pages/LetterSettings.jsx`; component-kit.md §14.3, ADR-111).
///
/// The read is the REAL [SettingsNotifier] over a Firestore double that
/// refuses with `permission-denied`, as the rules do in prod. Web's panel says
/// `Your letter settings could not be read — ` + failureDetail(e), and
/// failureDetail of an SDK error is §14.3's table; Letter settings' §14.1
/// block carries the same sentence as its detail. The save path's own refusal
/// is not the read's: a refused write never becomes the read's line.
library;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'home_harness.dart';
import 'letters_harness.dart';

const _denied = 'NoteLetter could not read this. Sign out and back in, or '
    'contact support.';
const _line = 'Your letter settings could not be read — $_denied';

FirebaseException _refusal() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

class _RefusedHome extends HomeReads {
  _RefusedHome() : super();
  @override
  Future<NewsletterSettings> getNewsletterSettings() async => throw _refusal();
}

class _RefusedLetters extends LettersReads {
  _RefusedLetters() : super();
  @override
  Future<NewsletterSettings> getNewsletterSettings() async => throw _refusal();
}

class _Settings extends FirestoreService {
  _Settings(this.answer) : super.stub();
  Future<NewsletterSettings> Function() answer;
  @override
  String? get currentUid => 'u1';
  @override
  Future<NewsletterSettings> getNewsletterSettings() => answer();
}

/// Refuses every PUT with the server's envelope.
class _Refuse implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error": "deliveryTime must be HH:MM."}',
    400,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void _reset() {
  KitPageTools.instance.reset();
  LocalFlags.resetForTest();
  LocalFlags.sourceView.value = 'list';
  LocalFlags.onboardDismissed.value = true;
}

void main() {
  setUp(_reset);
  tearDown(FirestoreService.resetInstance);

  group('SettingsNotifier', () {
    test('a refused read keeps §14.3\'s sentence as the read\'s refusal', () async {
      FirestoreService.instance = _Settings(() async => throw _refusal());
      final s = SettingsNotifier();
      await s.loadAll();
      expect(s.newsletter, isNull);
      expect(s.readError, _denied);
    });

    test('a read that answers clears the last refusal', () async {
      final fs = _Settings(() async => throw _refusal());
      FirestoreService.instance = fs;
      final s = SettingsNotifier();
      await s.loadAll();
      expect(s.readError, _denied);
      fs.answer = () async => const NewsletterSettings(enabled: true);
      await s.loadAll();
      expect(s.readError, isNull);
      expect(s.newsletter?.enabled, isTrue);
    });

    test('a refused save is the save\'s, never the read\'s', () async {
      FirestoreService.instance = _Settings(
        () async => const NewsletterSettings(enabled: true),
      );
      ApiService.instance.tokenProvider = () async => 'test-token';
      ApiService.instance.httpClientAdapter = _Refuse();
      addTearDown(ApiService.instance.resetTestSeams);
      final s = SettingsNotifier();
      await s.loadAll();
      final err = await s.setScheduledDelivery(
        enabled: true,
        deliveryTime: '7',
        timezone: 'UTC',
      );
      expect(err, 'deliveryTime must be HH:MM.');
      expect(s.error, 'deliveryTime must be HH:MM.');
      expect(s.readError, isNull);
    });
  });

  group('the settings panels say web\'s line', () {
    testWidgets('Home: Letter settings', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpHome(
        tester,
        _RefusedHome(),
        settings: SettingsNotifier(),
        size: const Size(1200, 3000),
      );
      expect(KitPageTools.instance.openSettings(), isTrue);
      await pumpFrames(tester, 4);
      expect(find.byType(KitLetterQuick), findsOneWidget);
      expect(find.widgetWithText(KitFailureInline, _line), findsOneWidget);
      expect(find.text('Could not load newsletter settings.'), findsNothing);
      expect(find.text('Reading your letter settings…'), findsNothing);
    });

    testWidgets('Letters: Letter settings', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpLetters(tester, _RefusedLetters(), settings: SettingsNotifier());
      expect(KitPageTools.instance.openSettings(), isTrue);
      await lettersFrames(tester, 4);
      expect(find.byType(KitLetterQuick), findsOneWidget);
      expect(find.widgetWithText(KitFailureInline, _line), findsOneWidget);
      expect(find.text('Could not load newsletter settings.'), findsNothing);
    });
  });
}
