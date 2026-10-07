/// Rescan all — the provider's rescan, beside its organized folders
/// (screens/sources.md: `fn_scan_organization`, "Rescan all and every folder's
/// rescan wait on one clock"; the reference's OrganizationPanel.jsx
/// `RescanAll`).
///
/// This client had only the per-folder rescan. The reference's Rescan all
/// sits in the provider's section header, calls `fn_scan_organization` with
/// no folder, reads "Scanning…" and holds every rescan of the provider while
/// a scan is in flight, counts the provider's cooldown down on its label with
/// the server's sentence as calm copy, and says any other refusal as §14.2 in
/// the panel — never a toast that is gone before it is read.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_folder.dart';
import 'package:flutter_app/pages/sources/organization_settings_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/cooldown.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Answers each request with [reply] — or holds it until [release] when
/// [held] is set; records what was sent.
class _Server implements HttpClientAdapter {
  _Server(this.reply);
  (int, Object) Function(RequestOptions o) reply;
  Completer<void>? held;
  final List<RequestOptions> sent = [];

  void release() => held?.complete();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    if (held != null) await held!.future;
    final (status, body) = reply(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> _envelope(String error, String code, [int? wait]) => {
      'error': error,
      'error_code': code,
      'request_id': 'a1b2c3d4',
      'retry_after_s': ?wait,
    };

class _Folders extends FirestoreService {
  _Folders(this.folders, {this.fail = false}) : super.stub();
  final List<CloudFolder> folders;
  final bool fail;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<CloudFolder>> subscribeCloudFolders(String provider) => fail
      ? Stream.error(Exception('permission-denied'))
      : Stream.value(folders.where((f) => f.provider == provider).toList());
}

const _papers = CloudFolder(
    id: 'f1',
    provider: 'notion',
    providerPath: '/Papers',
    name: 'Papers',
    organized: true);

Widget _panel() => ChangeNotifierProvider<OrgNotifier>(
      create: (_) => OrgNotifier(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
              child: OrganizedFoldersPanel(provider: 'notion')),
        ),
      ),
    );

Finder _link(String label) => find.widgetWithText(KitSettingLink, label);
KitSettingLink _linkOf(WidgetTester t, String label) =>
    t.widget<KitSettingLink>(_link(label));
Finder _folderRescan(String label) => find.widgetWithText(KitButton, label);

void main() {
  late DateTime now;
  Future<void> step(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 7, 12);
    Cooldowns.instance.clock = () => now;
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(() {
    Cooldowns.instance.resetForTest();
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  testWidgets(
      'idle: Rescan all sits in the folders\' header, live, and asks for the '
      'whole provider — no folder', (tester) async {
    FirestoreService.instance = _Folders(const [_papers]);
    final api = _Server((_) => (202, {'queued': true}));
    ApiService.instance.httpClientAdapter = api;
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    expect(
        find.ancestor(of: _link('Rescan all'), matching: find.byType(SectionHeader)),
        findsOneWidget,
        reason: 'the §3 header over the folders, as the reference\'s .lib-section-h');
    expect(_linkOf(tester, 'Rescan all').onTap, isNotNull);
    expect(_linkOf(tester, 'Rescan all').icon, isNull,
        reason: 'a bare link: it acts here, it does not go anywhere');

    await tester.tap(_link('Rescan all'));
    await tester.pumpAndSettle();
    expect(api.sent.single.path, endsWith('fn_scan_organization'));
    expect(api.sent.single.data, {'provider': 'notion'},
        reason: 'no folder_id: the whole provider');
    expect(find.byType(KitFailureInline), findsNothing);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'a scan that started says nothing — progress arrives on the '
            'folders, as on the reference');
  });

  testWidgets('with no organized folders yet, the provider can still be rescanned',
      (tester) async {
    FirestoreService.instance = _Folders(const []);
    ApiService.instance.httpClientAdapter = _Server((_) => (202, {'queued': true}));
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();
    expect(find.text('No organized folders yet.'), findsOneWidget);
    expect(_linkOf(tester, 'Rescan all').onTap, isNotNull);
  });

  testWidgets(
      'busy: "Scanning…" holds Rescan all AND every folder\'s rescan until the '
      'answer arrives, then both come back', (tester) async {
    FirestoreService.instance = _Folders(const [_papers]);
    final api = _Server((_) => (202, {'queued': true}))..held = Completer();
    ApiService.instance.httpClientAdapter = api;
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    await tester.tap(_link('Rescan all'));
    await tester.pump();
    expect(_link('Rescan all'), findsNothing);
    expect(_linkOf(tester, 'Scanning…').onTap, isNull,
        reason: 'held while its own request is in flight');
    expect(tester.widget<KitButton>(_folderRescan('Rescan')).onPressed, isNull,
        reason: 'one scan at a time per provider, as the reference\'s one '
            '`rescanning` flag holds every rescan control');
    expect(find.textContaining('0:'), findsNothing,
        reason: 'write before you move: never a countdown while in flight');

    api.release();
    await tester.pumpAndSettle();
    expect(_linkOf(tester, 'Rescan all').onTap, isNotNull);
    expect(tester.widget<KitButton>(_folderRescan('Rescan')).onPressed, isNotNull);
  });

  testWidgets(
      'the cooldown wait: 409 COOLDOWN with its number holds Rescan all and '
      'the folders on one clock, says the sentence once as calm copy, and '
      'gives both back at zero', (tester) async {
    FirestoreService.instance = _Folders(const [_papers]);
    const sentence = 'Scan requested too recently — try again in a few minutes';
    final api = _Server((_) => (409, _envelope(sentence, 'COOLDOWN', 2)));
    ApiService.instance.httpClientAdapter = api;
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    await tester.tap(_link('Rescan all'));
    await tester.pumpAndSettle();
    expect(_linkOf(tester, 'Rescan all · 0:02').wait, 2,
        reason: 'held, with the remaining time on its label');
    await tester.tap(_link('Rescan all · 0:02'));
    await tester.pump();
    expect(api.sent, hasLength(1), reason: 'a held link sends nothing');
    expect(_folderRescan('Rescan · 0:02'), findsOneWidget,
        reason: 'the cooldown is the PROVIDER\'s: the folder waits on it too');
    expect(find.text(sentence), findsOneWidget);
    expect(
        find.ancestor(of: find.text(sentence), matching: find.byType(KitWaitNote)),
        findsOneWidget,
        reason: 'a wait is calm copy, not §14.2');
    expect(find.byType(KitFailureInline), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await step(tester, const Duration(seconds: 1));
    expect(_link('Rescan all · 0:01'), findsOneWidget, reason: 'it counts down');
    await step(tester, const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_linkOf(tester, 'Rescan all').onTap, isNotNull);
    expect(find.text(sentence), findsNothing,
        reason: 'the sentence leaves with the wait');
  });

  testWidgets(
      'a refusal that is not the cooldown is §14.2 under the header, in the '
      'server\'s words — not a toast — and the next ask clears it',
      (tester) async {
    FirestoreService.instance = _Folders(const [_papers]);
    const sentence = 'Organization is not enabled for this provider.';
    var refuse = true;
    ApiService.instance.httpClientAdapter = _Server((_) => refuse
        ? (409, _envelope(sentence, 'NOT_ENABLED'))
        : (202, {'queued': true}));
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();

    await tester.tap(_link('Rescan all'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(KitFailureInline), matching: find.text(sentence)),
        findsOneWidget,
        reason: 'the server\'s sentence, verbatim, in the §14.2 slot');
    expect(find.byType(SnackBar), findsNothing,
        reason: 'it stays where it can be read');
    expect(
        tester.getTopLeft(find.byType(KitFailureInline)).dy,
        lessThan(tester.getTopLeft(find.text('/Papers')).dy),
        reason: 'said under the header, above the folders it concerns');
    expect(_linkOf(tester, 'Rescan all').onTap, isNotNull,
        reason: 'a failure does not hold the control');

    refuse = false;
    await tester.tap(_link('Rescan all'));
    await tester.pump();
    expect(find.byType(KitFailureInline), findsNothing,
        reason: 'the next ask clears the last answer before it is sent');
    await tester.pumpAndSettle();
  });

  testWidgets('an unread folder list still leaves the provider rescannable',
      (tester) async {
    FirestoreService.instance = _Folders(const [], fail: true);
    ApiService.instance.httpClientAdapter = _Server((_) => (202, {'queued': true}));
    await tester.pumpWidget(_panel());
    await tester.pumpAndSettle();
    expect(find.byType(KitFailureInline), findsOneWidget,
        reason: 'the subscription\'s own failure, first (C3)');
    expect(_linkOf(tester, 'Rescan all').onTap, isNotNull);
  });
}
