// KitTextField's value tracking (F-38, F-49). A TextField merges its style
// over Material 3's `bodyLarge`, whose 0.5 letter-spacing leaks into any face
// that does not pin its own — web's `.timefield input`, `.ss-input` and
// `.sf-desc` all track at 0, so an unpinned face draws ~8% wider than web's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  for (final face in KitFieldFace.values) {
    testWidgets('the ${face.name} face tracks at 0, value and placeholder',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: KitTextField(
            controller: TextEditingController(text: 'seed@noteletter.test'),
            placeholder: 'you@example.com',
            face: face,
          ),
        ),
      ));
      expect(Theme.of(tester.element(find.byType(KitTextField)))
              .textTheme
              .bodyLarge
              ?.letterSpacing,
          isNot(0),
          reason: 'the leak this pins against must exist, or the test proves '
              'nothing');
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.letterSpacing, 0);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintStyle!.letterSpacing, 0);
    });
  }
}
