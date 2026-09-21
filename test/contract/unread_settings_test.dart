import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/organization_settings.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// **C4 — a read swallowed into defaults, and then written back.**
///
/// `OrgNotifier._settings` starts at `const OrganizationSettings()`: threshold
/// 0.75, mode `split`, no providers. `loadSettings` caught everything under
/// *"Non-fatal — keep defaults"*, which left it there — indistinguishable from
/// an account that really is on the defaults.
///
/// That is worse than an unrendered failure, because `updateSettings` sends a
/// PARTIAL. The panel drew the defaults as though they were stored, and one
/// nudge of the threshold slider saved the default MODE over whatever the
/// reader had chosen, from a screen that had never seen their settings. The
/// write was the damage; the missing notice was only how it stayed quiet.
///
/// The guard is on the WRITER, not only the screen. Two call sites cannot each
/// be relied on to remember, and a partial composed against unread state is
/// wrong however carefully the screen is written.

class _StubService extends FirestoreService {
  _StubService({this.settings, this.fail = false}) : super.stub();

  final OrganizationSettings? settings;
  final bool fail;

  @override
  String? get currentUid => 'u1';

  @override
  Future<OrganizationSettings> getOrganizationSettings() async {
    if (fail) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    return settings ?? const OrganizationSettings();
  }
}

void main() {
  tearDown(FirestoreService.resetInstance);

  test('a failed read is NOT "on the defaults"', () async {
    FirestoreService.instance = _StubService(fail: true);
    final org = OrgNotifier();
    await org.loadSettings();

    expect(org.settingsError, contains('Sign out and back in'));
    expect(org.settingsLoaded, isFalse,
        reason: 'the defaults are what it kept; the question is whether '
            'anything can tell that from a real read');
  });

  test('and the write REFUSES, which is the half that did the damage',
      () async {
    FirestoreService.instance = _StubService(fail: true);
    final org = OrgNotifier();
    await org.loadSettings();

    final err = await org.updateSettings({'confidence_threshold': 0.9});
    expect(err, isNotNull,
        reason: 'a partial composed against unread state sends the DEFAULTS '
            'for every key the reader did not touch');
    expect(err, contains('defaults'));
  });

  test('a successful read unlocks the write', () async {
    FirestoreService.instance = _StubService(
        settings: const OrganizationSettings(
            confidenceThreshold: 0.6, defaultReorgMode: 'copy'));
    final org = OrgNotifier();
    await org.loadSettings();

    expect(org.settingsError, isNull);
    expect(org.settingsLoaded, isTrue);
    expect(org.settings.confidenceThreshold, 0.6);
    expect(org.settings.defaultReorgMode, 'copy');

    // Deliberately NOT calling `updateSettings` here: past the guard it
    // reaches the real `Api`, which this suite has no double for, and a test
    // that waits 30s on a socket to prove a boolean is a test nobody runs.
    // `settingsLoaded` IS the guard's condition — the same fact, asserted
    // where it lives.
  });

  test('a Retry after a failure reads, and unlocks', () async {
    FirestoreService.instance = _StubService(fail: true);
    final org = OrgNotifier();
    await org.loadSettings();
    expect(org.settingsLoaded, isFalse);

    FirestoreService.instance =
        _StubService(settings: const OrganizationSettings());
    await org.loadSettings();

    expect(org.settingsError, isNull);
    expect(org.settingsLoaded, isTrue,
        reason: 'the panel Retry has to be able to clear the state it shows');
  });

  // ── the SCREENS, over the same failure ────────────────────────────────────

  testWidgets('the org panel says so instead of vanishing', (tester) async {
    await pumpSources(tester, SourcesStubService(orgSettingsFail: true));
    await tester.pump();

    // `settings.providers` is empty on the defaults, so the panel's own
    // `enabledProviders.isEmpty` check took it off the screen entirely: the
    // reader lost the controls AND the reason in one step.
    expect(find.byType(KitFailureBlock), findsWidgets);
    expect(find.textContaining('Sign out and back in'), findsOneWidget);
  });

  testWidgets('and draws no controls at all until a read succeeded',
      (tester) async {
    await pumpSources(tester, SourcesStubService(orgSettingsFail: true));
    await tester.pump();

    // The threshold slider is the control whose nudge did the damage.
    expect(find.byType(Slider), findsNothing,
        reason: 'a control drawn from unread state saves what it is showing');
  });

  testWidgets('the provider cards are WITHHELD when the list was never read',
      (tester) async {
    await pumpSources(tester, SourcesStubService(),
        cloud: UnreadCloud('integrations-unreadable'));
    await tester.pump();

    // `integrationFor` answers null for every provider on an unread list, and
    // a card's whole meaning is whether that service is connected. Drawing
    // them is not a missing notice — it is an instruction to re-run OAuth
    // against a service the reader is already connected to.
    expect(find.textContaining('integrations-unreadable'), findsOneWidget);
    expect(find.text('Connect'), findsNothing,
        reason: 'the cards were withheld, not drawn wrong');
  });
}
