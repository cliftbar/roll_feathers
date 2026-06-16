import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('settings UI', () {
    testWidgets('dark mode toggle cycles Light Mode → Dark Mode', (tester) async {
      await startApp(tester);
      await openSettings(tester);

      expect(find.text('Light Mode'), findsOneWidget);

      await tester.tap(find.text('Light Mode'));
      await tester.pumpAndSettle();

      // Drawer dismisses after tap; reopen to read new label
      await openSettings(tester);
      expect(find.text('Dark Mode'), findsOneWidget);
    });

    testWidgets('rule scripts screen lists saved scripts', (tester) async {
      await startApp(tester);
      await openSettingsItem(tester, 'Rule Scripts');

      expect(find.text('Saved Scripts'), findsOneWidget);
      expect(find.text('Basic Blink'), findsOneWidget);
    });

    testWidgets('rule script checkbox can be toggled', (tester) async {
      await startApp(tester);
      await openSettingsItem(tester, 'Rule Scripts');

      // Find the Checkbox inside the ListTile that has 'Basic Blink' as its title
      final basicBlinkTile = find.ancestor(
        of: find.text('Basic Blink'),
        matching: find.byType(ListTile),
      );
      final checkbox = find.descendant(
        of: basicBlinkTile,
        matching: find.byType(Checkbox),
      );

      final initialValue = tester.widget<Checkbox>(checkbox).value;

      await tester.tap(checkbox);
      // pumpAndSettle can hang when accumulated stream listeners from prior tests
      // keep rebuilding; a bounded pump is sufficient to see the value change.
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<Checkbox>(checkbox).value, isNot(initialValue));
    });
  });
}
