// F-101 — the cloud connectors draw their vendors' own marks (web
// `shared/ProviderLogo.jsx`), not generic glyphs: the connect card's plate,
// the Import from / Organized folders headers, Settings → Sources' rows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/shared/cloud_providers.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: w)),
  ));
}

void main() {
  test('every connector the app offers has its vendor mark', () {
    for (final p in cloudProviders.keys) {
      expect(KitProviderLogo.has(p), isTrue, reason: p);
      expect(KitProviderLogo.providerOf(cloudProviders[p]!.icon), p,
          reason: 'the table\'s glyph is $p\'s mark, through KitGlyph');
    }
    expect(KitProviderLogo.providerOf(Icons.cloud_outlined), isNull);
  });

  testWidgets('the connect card plate holds the mark at 22', (tester) async {
    await _pump(
        tester,
        const SizedBox(
            width: 180,
            child: KitConnectCard(
                icon: KitProviderLogo.dropbox,
                title: 'Dropbox',
                subtitle: 'Files & folders',
                status: 'Connect')));
    final logo = find.byType(KitProviderLogo);
    expect(logo, findsOneWidget);
    expect(tester.widget<KitProviderLogo>(logo).provider, 'dropbox');
    expect(tester.getSize(logo), const Size(22, 22));
    expect(find.byType(Icon), findsNothing,
        reason: 'no generic glyph stands in for the vendor');
  });

  testWidgets('a provider setting row sits on the white plate', (tester) async {
    await _pump(
        tester,
        const KitSettingRow(
            icon: KitProviderLogo.notion, title: 'Notion', trailing: []));
    final plate = tester.widget<Container>(find
        .ancestor(
            of: find.byType(KitProviderLogo), matching: find.byType(Container))
        .first);
    final d = plate.decoration as BoxDecoration;
    expect(d.color, const Color(0xFFFFFFFF),
        reason: 'Notion\'s mark is black: its plate stays light in dark mode');
  });
}
