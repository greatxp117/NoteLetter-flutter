import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/activity_page.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// **C1 — a failed activity feed says so, and does not say the opposite.**
///
/// `subscribeActivity` answered a snapshot error with `controller.add(const
/// [])`, so the notifier's `onError` was dead code and the screen drew its §7
/// empty state — "Nothing has happened yet" — on a rules or index failure.
/// That is the ADR-070 shape at its worst: not a missing message, but a
/// confident and false one, on the screen whose entire subject is the record
/// of what the account has done.
///
/// Two halves are asserted here and they fail differently. **EMPTY-ONLY** is
/// the original defect: §7 standing in for §14. **ORDER** is the one hiding
/// behind it — the block was gated on `rows.isEmpty`, so a feed that loaded
/// once and then failed kept its rows and said nothing at all, which is worse
/// than the first: stale rows read as current.
///
/// The service half — that a Firestore snapshot error reaches this notifier
/// rather than being mapped to an empty list — cannot be pumped here. There is
/// no Firebase app in a plain widget test and this client has no fake
/// Firestore (`test/widget_test.dart` and `test/contract/support_footer_test`
/// both record the same limit), so the erroring stream is injected at the
/// notifier's own boundary and the real subscription is the device run's.
/// Saying which half is gated is the point: an unstated gap reads as coverage.

class _StubActivity extends ActivityNotifier {
  _StubActivity({List<ActivityItem> items = const [], String? error})
      : _items = items,
        _error = error;

  final List<ActivityItem> _items;
  String? _error;

  @override
  void start({int limit = 100}) {}
  @override
  Future<void> refresh() async => retried = true;

  bool retried = false;

  @override
  List<ActivityItem> get items => _items;
  @override
  String? get error => _error;
  @override
  bool get isLoading => false;
  @override
  int get newestEventAt => 0;

  /// What the real notifier does on a stream error, once the service stopped
  /// swallowing it: keep whatever was last received, and set the sentence.
  void failWith(String e) {
    _error = e;
    notifyListeners();
  }
}

class _StubDocuments extends DocumentsNotifier {
  @override
  void start() {}
  @override
  List<Document> get documents => const [];
}

ActivityItem _event(String id) => ActivityItem(
      kind: 'event',
      id: id,
      type: 'document_added',
      status: 'success',
      level: 'info',
      title: 'A source you added',
      createdAt: 1757000000000,
    );

Future<void> _pump(WidgetTester tester, _StubActivity activity) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ActivityNotifier>.value(value: activity),
      ChangeNotifierProvider<DocumentsNotifier>(
          create: (_) => _StubDocuments()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ActivityPage()),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('EMPTY-ONLY — a failed feed draws §14, never the empty state',
      (tester) async {
    await _pump(tester, _StubActivity(error: 'permission-denied'));

    expect(find.byType(KitFailureBlock), findsOneWidget,
        reason: 'the failure has to be said');
    expect(find.byType(KitEmptyState), findsNothing,
        reason: '§7 is an offer; drawn here it asserts an empty account');
    expect(find.textContaining('permission-denied'), findsOneWidget,
        reason: "§14 PARTS — the server's own sentence, quoted");
  });

  testWidgets('ORDER — a feed that loaded and THEN failed says so, above rows',
      (tester) async {
    final activity = _StubActivity(items: [_event('a')]);
    await _pump(tester, activity);
    expect(find.byType(KitFailureBlock), findsNothing);
    expect(find.byType(KitTimeline), findsOneWidget);

    activity.failWith('unavailable');
    await tester.pump();

    expect(find.byType(KitFailureBlock), findsOneWidget,
        reason: 'stale rows with no notice read as current');
    expect(find.byType(KitTimeline), findsOneWidget,
        reason: 'what did load is still true, and is kept');
    // Above, not below: the notice has to be met before the rows it qualifies.
    expect(
      tester.getTopLeft(find.byType(KitFailureBlock)).dy <
          tester.getTopLeft(find.byType(KitTimeline)).dy,
      isTrue,
    );
  });

  testWidgets('§7 still speaks when nothing failed', (tester) async {
    await _pump(tester, _StubActivity());
    expect(find.byType(KitEmptyState), findsOneWidget);
    expect(find.byType(KitFailureBlock), findsNothing);
  });

  testWidgets('the block carries a Retry that reaches the notifier',
      (tester) async {
    final activity = _StubActivity(error: 'unavailable');
    await _pump(tester, activity);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(activity.retried, isTrue,
        reason: 'a Retry that cannot re-subscribe is a control that lies');
  });
}
