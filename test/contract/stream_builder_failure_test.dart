import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/cloud_folder.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/organization_suggestion.dart';
import 'package:flutter_app/pages/letters/pinned_sources.dart';
import 'package:flutter_app/pages/sources/organization_settings_panel.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// **C3 — two `StreamBuilder`s that never asked `hasError`.**
///
/// A `StreamBuilder` hands the failure to the builder and waits to be asked.
/// `snap.data ?? const []` does not ask, so a failed stream and an empty one
/// are one value — and both of these screens answer "empty" by saying
/// something confident:
///
/// * `PinnedSources` REMOVES ITSELF. A reader who had pinned sources for the
///   next letter saw no panel, which reads as having pinned nothing — on the
///   one screen where the pins are the whole point.
/// * `OrganizedFoldersPanel` says "No organized folders yet.", an answer about
///   the account given when nothing about the account was read.
///
/// Driven through C1's seam, so the real widgets run against a stream that
/// fails on command.

class _StubService extends FirestoreService {
  _StubService({this.pinned, this.folders}) : super.stub();

  final Stream<List<Document>>? pinned;
  final Stream<List<CloudFolder>>? folders;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribePinnedDocuments() =>
      pinned ?? const Stream.empty();

  @override
  Stream<List<CloudFolder>> subscribeCloudFolders(String provider) =>
      folders ?? const Stream.empty();
}

Document _doc(String id) => Document(
      id: id,
      userId: 'u1',
      title: 'A pinned volume',
      type: 'pdf',
      status: DocumentStatus.complete,
      createdAt: 1757000000000,
    );

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

/// The kit uppercases a `SectionHeader`'s label, so a literal finder misses it
/// — the same trap the folio set in C2's tests.
Finder textLike(String needle) => find.byWidgetPredicate((w) =>
    w is Text &&
    (w.data ?? '').toLowerCase().contains(needle.toLowerCase()));

void main() {
  tearDown(FirestoreService.resetInstance);

  group('PinnedSources', () {
    testWidgets('a failed stream says so instead of vanishing', (tester) async {
      final source = StreamController<List<Document>>();
      FirestoreService.instance = _StubService(pinned: source.stream);

      await _pump(tester, const PinnedSources(settings: null));
      source.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      await tester.pump();

      expect(find.byType(KitFailureInline), findsOneWidget,
          reason: 'the panel removing itself reads as having pinned nothing');
      expect(find.textContaining('Sign out and back in'), findsOneWidget);
    });

    testWidgets('and still vanishes when there is genuinely nothing pinned',
        (tester) async {
      final source = StreamController<List<Document>>();
      FirestoreService.instance = _StubService(pinned: source.stream);

      await _pump(tester, const PinnedSources(settings: null));
      source.add(const []);
      await tester.pump();

      expect(find.byType(KitFailureInline), findsNothing);
      expect(find.textContaining('Pinned'), findsNothing,
          reason: 'an empty panel is right to be absent — that is a real '
              'answer about the account');
    });

    testWidgets('a loaded list still renders', (tester) async {
      final source = StreamController<List<Document>>();
      FirestoreService.instance = _StubService(pinned: source.stream);

      await _pump(tester, const PinnedSources(settings: null));
      source.add([_doc('d1')]);
      await tester.pump();

      expect(find.byType(KitFailureInline), findsNothing);
      expect(find.textContaining('A pinned volume'), findsOneWidget);
    });
  });

  group('OrganizedFoldersPanel', () {
    testWidgets('a failed stream is not "No organized folders yet."',
        (tester) async {
      final source = StreamController<List<CloudFolder>>();
      FirestoreService.instance = _StubService(folders: source.stream);

      await _pump(tester, const OrganizedFoldersPanel(provider: 'drive'));
      source.addError(StateError('unavailable'));
      await tester.pump();

      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.textContaining('No organized folders yet'), findsNothing,
          reason: 'an answer about the account, given when nothing about the '
              'account was read');
    });

    testWidgets('and the empty answer survives for a real empty', (tester) async {
      final source = StreamController<List<CloudFolder>>();
      FirestoreService.instance = _StubService(folders: source.stream);

      await _pump(tester, const OrganizedFoldersPanel(provider: 'drive'));
      source.add(const []);
      await tester.pump();

      expect(find.textContaining('No organized folders yet'), findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
    });
  });

  // ── The other half of C3: two SECTIONS whose answer to "empty" is to vanish
  //
  // `CloudNotifier._jobsError` and `OrgNotifier._suggestionsError` have each
  // carried an INV-24 comment since they were written — *an unread job list
  // renders as "no imports running", which is exactly what a reader watching
  // an import wants to know is false* — and no page had ever read either
  // getter. Hiding the section IS the failure mode, not a symptom of it.

  group('Sources sections', () {
    testWidgets('a failed import-jobs subscription is a notice, not a gap',
        (tester) async {
      final jobs = StreamController<List<ImportJob>>.broadcast();
      await pumpSources(tester, SourcesStubService(jobs: jobs.stream));

      jobs.addError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      await tester.pump();
      await tester.pump();

      expect(textLike('Import activity'), findsOneWidget,
          reason: 'the section vanished entirely, which reads as no imports');
      expect(find.textContaining('You appear to be offline'), findsOneWidget);
      // Unread is not zero (§8, ADR-109) — the label stays, the count goes.
      expect(textLike('Import activity · '), findsNothing);
    });

    testWidgets('and stays absent when there are genuinely no imports',
        (tester) async {
      final jobs = StreamController<List<ImportJob>>.broadcast();
      await pumpSources(tester, SourcesStubService(jobs: jobs.stream));

      jobs.add(const []);
      await tester.pump();
      await tester.pump();

      expect(textLike('Import activity'), findsNothing,
          reason: 'an absent section is the right answer to a real empty');
    });

    testWidgets('a failed suggestions subscription is a notice, not a gap',
        (tester) async {
      final sug = StreamController<List<OrganizationSuggestion>>.broadcast();
      await pumpSources(tester, SourcesStubService(suggestions: sug.stream));

      sug.addError(FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition'));
      await tester.pump();
      await tester.pump();

      expect(textLike('Organization suggestions'), findsOneWidget);
      expect(find.textContaining('not ready on the server yet'), findsOneWidget);
      expect(textLike('Organization suggestions · '), findsNothing);
    });
  });
}
