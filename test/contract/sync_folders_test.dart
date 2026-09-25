import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/pages/sources/sync_folder_picker.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// `screens/sources.md` §Sync control — the sync-folder scope (QUEUE F-47).
///
/// This client had no way to set `folder_ids`, so Sync now was disabled for
/// good and two sentences told the reader to "choose sync folders" on a screen
/// that could not. Each case is one clause of that section, over the REAL
/// `CloudNotifier` and a canned transport: what is sent, and that the panel
/// moves only on what came back.

class _Recorder implements HttpClientAdapter {
  _Recorder(this.reply);

  final (int, Object) Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  List<RequestOptions> to(String path) => [
    for (final o in sent)
      if (o.path.endsWith(path)) o,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    final (status, body) = reply(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _listing = {
  'items': [
    {'id': 'fld-reading-2026', 'name': 'Reading', 'type': 'folder'},
    {'id': 'fld-b', 'name': 'Taxes', 'type': 'folder'},
    {
      'id': 'file-1',
      'name': 'loose.pdf',
      'type': 'file',
      'mime_type': 'application/pdf',
    },
  ],
  'folderId': 'root',
  'provider': 'google_drive',
};

Map<String, dynamic> _integration(List<String> ids) => {
  'provider': 'google_drive',
  'token_valid': true,
  'sync_config': {
    'folder_ids': ids,
    'include_types': ['pdf'],
  },
};

(int, Object) Function(RequestOptions) _server(
  (int, Object) Function(Map body) settings,
) => (o) {
  if (o.path.endsWith('/fn_list_cloud_files')) return (200, _listing);
  return settings(o.data as Map);
};

(int, Object) _refuse(Map _) => (
  400,
  {
    'error': 'folder_ids must be at most 20 strings',
    'error_code': 'VALIDATION',
  },
);

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() => ApiService.instance.resetTestSeams());

  /// The panel as the Sources screen mounts it: built from the notifier, so
  /// the only way a chip appears is the notifier holding a returned
  /// integration.
  Future<CloudNotifier> pumpPanel(
    WidgetTester tester, {
    List<String> stored = const [],
  }) async {
    final c = QuietCloud();
    final seed = CloudIntegration(
      provider: 'google_drive',
      tokenValid: true,
      folderIds: stored,
      includeTypes: const ['pdf'],
    );
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<CloudNotifier>.value(
        value: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer<CloudNotifier>(
                builder: (_, cloud, __) => SyncSettingsPanel(
                  providerId: 'google_drive',
                  integration: cloud.integrationFor('google_drive') ?? seed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    return c;
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.text('Choose folders…'));
    await tester.pumpAndSettle();
  }

  Finder remove(String id) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Remove folder $id',
    ),
    matching: find.byIcon(Icons.close),
  );

  Finder check(String name) => find.descendant(
    of: find.byKey(ValueKey('sync-folder-$name')),
    matching: find.byType(Checkbox),
  );

  testWidgets('the picker lists folders only, each with its disclosure', (
    tester,
  ) async {
    final r = _Recorder(_server(_refuse));
    ApiService.instance.httpClientAdapter = r;
    await pumpPanel(tester);
    expect(find.text('0/20'), findsOneWidget);
    await openPicker(tester);

    expect(
      r.to('/fn_list_cloud_files').single.queryParameters,
      {'provider': 'google_drive'},
      reason: 'the root is the listing with no folderId',
    );
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Taxes'), findsOneWidget);
    expect(
      find.text('loose.pdf'),
      findsNothing,
      reason: 'folders-only mode lists no files',
    );
    expect(
      find.text('What’s in here?'),
      findsNWidgets(2),
      reason: '§Folder contents is on every folder row',
    );
    expect(
      r.to('/fn_scan_cloud_folder'),
      isEmpty,
      reason: 'a client MUST NOT scan the rows it lists',
    );
    expect(find.text('Sync 0 folders'), findsOneWidget);
  });

  testWidgets('confirm sends the whole list; chips come from the answer', (
    tester,
  ) async {
    final r = _Recorder(
      _server(
        (body) => (
          200,
          {'integration': _integration(List<String>.from(body['folder_ids']))},
        ),
      ),
    );
    ApiService.instance.httpClientAdapter = r;
    await pumpPanel(tester, stored: const ['fld-b']);
    await tester.tap(find.text('Change folders…'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Checkbox>(check('fld-b')).value,
      isTrue,
      reason: 'the picker opens on the stored scope',
    );
    await tester.tap(check('fld-reading-2026'));
    await tester.pump();
    expect(
      find.text('fld-reading-20…'),
      findsNothing,
      reason: 'a draft selection is not a saved folder',
    );
    await tester.tap(find.text('Sync 2 folders'));
    await tester.pumpAndSettle();

    final body = r.to('/fn_sync_settings').single.data as Map;
    expect(body, {
      'provider': 'google_drive',
      'folder_ids': ['fld-b', 'fld-reading-2026'],
    }, reason: 'a partial body with only the changed key, the list whole');
    expect(
      find.text('fld-reading-20…'),
      findsOneWidget,
      reason: 'the chip is the returned integration\'s id, cut at 14',
    );
    expect(find.text('2/20'), findsOneWidget);
    expect(
      find.byType(SyncFolderPicker),
      findsNothing,
      reason: 'a saved choice closes the picker',
    );
  });

  testWidgets('a refused save moves nothing and keeps the draft', (
    tester,
  ) async {
    final r = _Recorder(_server(_refuse));
    ApiService.instance.httpClientAdapter = r;
    await pumpPanel(tester);
    await openPicker(tester);
    await tester.tap(check('fld-b'));
    await tester.pump();
    await tester.tap(find.text('Sync 1 folder'));
    await tester.pumpAndSettle();

    expect(
      find.byType(SyncFolderPicker),
      findsOneWidget,
      reason: 'closing on a refusal throws away what the reader chose',
    );
    expect(
      find.descendant(
        of: find.byType(KitFailureInline),
        matching: find.text('folder_ids must be at most 20 strings'),
      ),
      findsOneWidget,
      reason: '§14.2 inline, the server\'s sentence',
    );
    expect(tester.widget<Checkbox>(check('fld-b')).value, isTrue);
    expect(
      find.text('0/20'),
      findsOneWidget,
      reason: 'the stored scope did not move',
    );
    expect(find.text('fld-b'), findsNothing, reason: 'no chip for a refusal');
  });

  testWidgets('a chip\'s remove sends the list without it, and waits', (
    tester,
  ) async {
    var refuse = true;
    final r = _Recorder(
      _server(
        (body) => refuse
            ? _refuse(body)
            : (
                200,
                {
                  'integration': _integration(
                    List<String>.from(body['folder_ids']),
                  ),
                },
              ),
      ),
    );
    ApiService.instance.httpClientAdapter = r;
    await pumpPanel(tester, stored: const ['fld-a', 'fld-b']);
    expect(find.text('fld-a'), findsOneWidget);
    expect(find.text('2/20'), findsOneWidget);

    await tester.tap(remove('fld-a'));
    await tester.pumpAndSettle();
    expect((r.to('/fn_sync_settings').last.data as Map)['folder_ids'], [
      'fld-b',
    ]);
    expect(
      find.text('fld-a'),
      findsOneWidget,
      reason: 'a refused remove leaves the chip — write before move',
    );
    expect(find.byType(KitFailureInline), findsOneWidget);

    refuse = false;
    await tester.tap(remove('fld-a'));
    await tester.pumpAndSettle();
    expect(find.text('fld-a'), findsNothing);
    expect(find.text('fld-b'), findsOneWidget);
  });

  testWidgets('at the cap a toggle no-ops and says why', (tester) async {
    final full = [for (var i = 0; i < 20; i++) 'f$i'];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SyncFolderPicker(
              provider: 'google_drive',
              initial: full,
              onConfirm: (_) async => null,
              onCancel: () {},
              list: (_) async => _listing,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(check('fld-b'));
    await tester.pump();
    expect(tester.widget<Checkbox>(check('fld-b')).value, isFalse);
    expect(
      find.text(
        '20-folder limit reached — import these first, then pick more.',
      ),
      findsOneWidget,
    );
    expect(find.text('20/20 folders selected'), findsOneWidget);
  });

  testWidgets('a failed listing is a failure, never "No subfolders here."', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SyncFolderPicker(
            provider: 'notion',
            initial: const [],
            onConfirm: (_) async => null,
            onCancel: () {},
            list: (_) async =>
                throw const ApiException(502, 'Notion did not answer.'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notion did not answer.'), findsOneWidget);
    expect(find.text('No subfolders here.'), findsNothing);
    expect(
      find.textContaining('Notion passes along'),
      findsNothing,
      reason: 'the advisory rides a listing that answered',
    );
  });

  testWidgets('Notion carries its standing advisory (ADR-026 §3)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SyncFolderPicker(
            provider: 'notion',
            initial: const [],
            onConfirm: (_) async => null,
            onCancel: () {},
            list: (_) async => {'items': <Object>[]},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Notion passes along only the pages you ticked'),
      findsOneWidget,
    );
    expect(
      find.text('No subfolders here.'),
      findsOneWidget,
      reason: 'empty is a claim about a listing that answered',
    );
  });
}
