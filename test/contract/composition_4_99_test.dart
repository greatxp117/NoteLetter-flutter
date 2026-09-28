/// The 4.99.0 tandem (ADR-132; CHANGELOG 4.99.0 tandem 3): ask.md's citation
/// corner, asserted as the rule the pill calls — a pill wide, `--r-xl` on a
/// phone. The Library half is library_hero_test.dart.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/chat_page.dart';
import 'package:flutter_app/theme/app_radius.dart';
import 'package:flutter_app/theme/app_spacing.dart';

void main() {
  test('a phone caps the citation at --r-xl (20), never 22', () {
    expect(citationRadius(390), AppRadius.xlR);
    expect(AppRadius.xl, 20);
    expect(citationRadius(AppSpacing.compactWidth - 1), AppRadius.xlR);
  });

  test('wide, the citation is a true pill', () {
    expect(citationRadius(AppSpacing.compactWidth), BorderRadius.circular(999));
    expect(citationRadius(1200), BorderRadius.circular(999));
  });
}
