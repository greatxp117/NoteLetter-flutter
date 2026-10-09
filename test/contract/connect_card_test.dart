import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/pages/settings/organization_section.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// One connect-card pattern (ruled 2026-10-08: "web's fixed card",
/// component-kit §5.1, `screens/sources.md` §Composition).
///
/// This client's card carried Browse files…, Sync now, Enable
/// auto-organization and Disconnect under its pill, a reconnect notice and a
/// footnote for the sync-now sentence. The reference keeps the card to its four
/// parts — iconbox → title → subtitle → status pill — and hangs the rest under
/// a §3 header per provider ("Import from {provider}", web `CloudImportPanel`,
/// `ed461b3`). Organizing is enabled from Settings (`screens/settings.md`
/// §Organization card), which is where the reference keeps that door.

class _ConnectedCloud extends QuietCloud {
  _ConnectedCloud(this.integration);
  final CloudIntegration integration;

  @override
  CloudIntegration? integrationFor(String provider) =>
      provider == integration.provider ? integration : null;
}

Finder _inCard(Finder f) =>
    find.descendant(of: find.byType(KitConnectCard), matching: f);

Finder _link(String label) => find.widgetWithText(KitSettingLink, label);

/// The pill by its label — it draws the label in mono caps.
Finder _pill(String label, {bool? positive}) => find.byWidgetPredicate((w) =>
    w is KitStatusPill &&
    w.label == label &&
    (positive == null || w.positive == positive));

void main() {
  group('the card is fixed', () {
    testWidgets('four parts, and nothing a call site can add', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: KitConnectCard(
            icon: Icons.cloud_outlined,
            title: 'OneDrive',
            subtitle: 'Files & folders',
            status: 'Connect',
          ),
        ),
      ));
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(find.text('OneDrive'), findsOneWidget);
      expect(find.text('Files & folders'), findsOneWidget);
      expect(_pill('Connect', positive: false), findsOneWidget);
      expect(find.byType(KitButton), findsNothing);
    });

    testWidgets('Sources: no control inside any card; the pill says Connected',
        (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true, folderIds: ['f1'])));
      expect(find.byType(KitConnectCard), findsNWidgets(4));
      expect(_inCard(find.byType(KitButton)), findsNothing);
      expect(_inCard(find.byType(KitSettingLink)), findsNothing);
      expect(_inCard(find.text('Sync now')), findsNothing);
      expect(
          find.descendant(
              of: find.widgetWithText(KitConnectCard, 'Google Drive'),
              matching: _pill('Connected', positive: true)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.widgetWithText(KitConnectCard, 'OneDrive'),
              matching: _pill('Connect', positive: false)),
          findsOneWidget);
      expect(find.text('Enable auto-organization'), findsNothing,
          reason: 'organizing is enabled from Settings now');
    });
  });

  group('Import from {provider}', () {
    testWidgets('a connected provider gets its header and three links',
        (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true, folderIds: ['f1'])));
      expect(find.text('IMPORT FROM GOOGLE DRIVE'), findsOneWidget);
      expect(find.textContaining(RegExp('IMPORT FROM (ONEDRIVE|NOTION|DROPBOX)')),
          findsNothing, reason: 'only a connected provider has a block');
      for (final l in ['Sync now', 'Sync settings', 'Browse files…']) {
        expect(_link(l), findsOneWidget, reason: l);
      }
    });

    testWidgets('the no-folders sentence is under the header, not in the card',
        (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true)));
      const sentence = 'Nothing to sync — choose sync folders first.';
      expect(find.text(sentence), findsOneWidget);
      expect(_inCard(find.text(sentence)), findsNothing);
      final syncNow =
          tester.widget<KitSettingLink>(_link('Sync now'));
      expect(syncNow.onTap, isNull, reason: 'held with its reason on screen');
    });

    testWidgets('Sync settings opens the panel, expanded, with no second header',
        (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true, folderIds: ['f1'])));
      expect(find.byType(SyncSettingsPanel), findsNothing);
      await tester.ensureVisible(_link('Sync settings'));
      await tester.tap(_link('Sync settings'));
      await tester.pump();
      expect(find.byType(SyncSettingsPanel), findsOneWidget);
      expect(_link('Close settings'), findsOneWidget);
      expect(find.text('AUTO-SYNC'), findsOneWidget);
      expect(find.textContaining('SYNC · '), findsNothing,
          reason: 'the link is the disclosure; the panel draws no second one');
    });

    testWidgets('an expired sign-in: the banner is under the header, Browse held',
        (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive',
              tokenValid: false,
              folderIds: ['f1'],
              status: 'reconnect_required',
              statusReason: 'Google revoked the token.')));
      expect(
          find.textContaining(
              'Google Drive needs to be reconnected — its sign-in has expired.'),
          findsOneWidget);
      expect(find.textContaining('Google revoked the token.'), findsOneWidget);
      expect(_link('Reconnect'), findsOneWidget);
      expect(_inCard(_link('Reconnect')), findsNothing);
      expect(tester.widget<KitSettingLink>(_link('Browse files…')).onTap,
          isNull);
      expect(tester.widget<KitSettingLink>(_link('Sync now')).onTap, isNull);
    });
  });

  group('Settings → Organization', () {
    Future<void> mount(WidgetTester tester, CloudNotifier cloud) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CloudNotifier>.value(value: cloud),
          ChangeNotifierProvider<OrgNotifier>(create: (_) => QuietOrg()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
              body: SingleChildScrollView(child: OrganizationSection())),
        ),
      ));
      await tester.pump();
    }

    testWidgets('nothing while no provider is connected', (tester) async {
      await mount(tester, QuietCloud());
      expect(find.text('ORGANIZATION'), findsNothing);
      expect(find.byType(KitSettingRow), findsNothing);
    });

    testWidgets('a connected provider without a write grant: Enable organizing',
        (tester) async {
      await mount(
          tester,
          _ConnectedCloud(const CloudIntegration(
              provider: 'dropbox', tokenValid: true)));
      expect(find.text('ORGANIZATION'), findsOneWidget);
      expect(find.text('Dropbox'), findsOneWidget);
      expect(find.textContaining('Organizing needs permission'), findsOneWidget);
      expect(_link('Enable organizing'), findsOneWidget);
    });

    testWidgets('a write grant the provider withheld says so', (tester) async {
      await mount(
          tester,
          _ConnectedCloud(const CloudIntegration(
              provider: 'onedrive',
              tokenValid: true,
              orgScopeLevel: 'read')));
      expect(find.textContaining('Write access wasn’t granted'), findsOneWidget);
      expect(_link('Enable organizing'), findsOneWidget);
    });

    testWidgets('write-ready: the row points at Sources', (tester) async {
      await mount(
          tester,
          _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive',
              tokenValid: true,
              orgEnabled: true,
              orgWriteAccess: true)));
      expect(_link('Choose organized folders in Sources'), findsOneWidget);
      expect(_link('Enable organizing'), findsNothing);
    });
  });

  test('the organization block is read off the integration', () {
    final i = CloudIntegration.fromJson({
      'provider': 'google_drive',
      'organization': {
        'enabled': true,
        'write_access': true,
        'scope_level': 'write',
      },
    });
    expect(i.orgWriteReady, isTrue);
    expect(i.orgScopeLevel, 'write');
    final denied = CloudIntegration.fromJson({
      'provider': 'google_drive',
      'organization': {
        'enabled': true,
        'write_access': false,
        'scope_level': 'read',
      },
    });
    expect(denied.orgWriteReady, isFalse);
    expect(CloudIntegration.fromJson({'provider': 'x'}).orgWriteReady, isFalse);
  });
}
