import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/models/cloud_folder.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/organization_settings.dart';
import 'package:flutter_app/models/organization_suggestion.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/sources_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// Mounting the real Sources screen over streams that fail on command.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it: it is
/// the harness two suites share. It exists because Sources is where four of
/// §C's items land, and a second hand-written copy of this provider tree is a
/// second thing to be wrong — the same argument the gates here make about a
/// vocabulary written down twice.
///
/// The notifiers are REAL. Only the Firestore layer is doubled, through C1's
/// seam, so what is under test is the notifier body and the screen, not a
/// stub's getters.
class SourcesStubService extends FirestoreService {
  SourcesStubService({
    this.documents,
    this.jobs,
    this.suggestions,
    this.folders,
    this.orgSettings,
    this.orgSettingsFail = false,
  }) : super.stub();

  final Stream<List<Document>>? documents;
  final Stream<List<ImportJob>>? jobs;
  final Stream<List<OrganizationSuggestion>>? suggestions;
  final Stream<List<CloudFolder>>? folders;

  /// C4: the one-shot org-settings read, which `OrgNotifier.start` kicks off
  /// and which used to be swallowed into the defaults.
  final OrganizationSettings? orgSettings;
  final bool orgSettingsFail;

  int documentsSubscribed = 0;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) {
    documentsSubscribed++;
    return documents ?? Stream.value(const []);
  }

  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(const []);

  @override
  Stream<List<ImportJob>> subscribeCloudImportJobs({int limit = 50}) =>
      jobs ?? Stream.value(const []);

  @override
  Stream<List<OrganizationSuggestion>> subscribeOrganizationSuggestions() =>
      suggestions ?? Stream.value(const []);

  @override
  Stream<List<CloudFolder>> subscribeCloudFolders(String provider) =>
      folders ?? Stream.value(const []);

  @override
  Future<OrganizationSettings> getOrganizationSettings() async {
    if (orgSettingsFail) throw StateError('settings-unreadable');
    return orgSettings ?? const OrganizationSettings();
  }
}

/// The real notifiers, with only their HTTP reads quieted.
///
/// `start()` is NOT overridden — the subscription it opens is the thing under
/// test. What is stubbed is the one-shot `Api` read each of them also kicks
/// off, which in a widget test reaches a real Dio client and leaves its
/// timeout timer pending after the tree is gone.
class QuietCloud extends CloudNotifier {
  @override
  Future<void> loadIntegrations() async {}
}

/// `OrgNotifier` unmodified. Its `loadSettings` goes through the doubled
/// Firestore layer, not `Api`, so there is no socket to quiet — and C4's
/// subject is precisely what that read does when it fails.
typedef QuietOrg = OrgNotifier;

/// A `CloudNotifier` whose integrations read has already failed.
///
/// The real `loadIntegrations` goes through `Api`, not Firestore, and this
/// client has no seam at that layer yet (C5 and C8 are where that lands), so
/// the NOTIFIER half of C4's cloud site is not gated here — only the screen's
/// answer to it. Saying which half is gated is the point: an unstated gap
/// reads as coverage.
class UnreadCloud extends CloudNotifier {
  UnreadCloud(this.message);

  final String message;

  @override
  Future<void> loadIntegrations() async {}
  @override
  String? get integrationsError => message;
  @override
  bool get integrationsLoaded => false;
}

class StubTags extends TagsNotifier {
  @override
  void start() {}
  @override
  List<Tag> get tags => const [];
}

class StubActivity extends ActivityNotifier {
  @override
  void start({int limit = 100}) {}
  @override
  List<ActivityItem> get items => const [];
}

/// Mounts [SourcesPage] with the real `CloudNotifier`, `OrgNotifier` and
/// `DocumentsNotifier` over [service].
Future<void> pumpSources(WidgetTester tester, SourcesStubService service,
    {DocumentsNotifier? documents, CloudNotifier? cloud}) async {
  FirestoreService.instance = service;
  // The harness that swaps the singleton puts it back. Leaving that to each
  // caller is what `test_isolation_test` refuses, and it was right to: this
  // file assigned the instance and named no reset, so the first suite to use
  // it would have leaked into whatever ran next.
  addTearDown(FirestoreService.resetInstance);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<DocumentsNotifier>(
          create: (_) => documents ?? DocumentsNotifier()),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags()),
      ChangeNotifierProvider<CloudNotifier>(create: (_) => cloud ?? QuietCloud()),
      ChangeNotifierProvider<OrgNotifier>(create: (_) => QuietOrg()),
      ChangeNotifierProvider<ActivityNotifier>(create: (_) => StubActivity()),
      ChangeNotifierProvider<UploadNotifier>(create: (_) => UploadNotifier()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: SourcesPage()),
    ),
  ));
  await tester.pump();   // lets the post-frame `start()` calls run
  await tester.pump();

  // The real `CloudNotifier` runs a timer for its completion notice, and a
  // widget test fails on a pending one. Unmounting lets the providers dispose
  // their notifiers, which is also the only thing here that proves `dispose`
  // cancels what `start` began.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
