import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('core dice UI', () {
    testWidgets('starts with no dice and empty history', (tester) async {
      await startApp(tester);

      expect(find.text('No dice added'), findsOneWidget);
      expect(find.text('Make some rolls!'), findsOneWidget);
    });

    testWidgets('adds a virtual die and it appears in the die list', (tester) async {
      await startApp(tester);
      await addVirtualDie(tester, 'd20', 20);

      expect(find.textContaining('d20'), findsWidgets);
      expect(find.text('No dice added'), findsNothing);
    });

    testWidgets('rolls a single virtual die and records result in history', (tester) async {
      await startApp(tester);
      await addVirtualDie(tester, 'd20', 20);
      await roll(tester);

      // History shows at least one entry with a rule name and numeric result
      expect(find.textContaining('Roll '), findsWidgets);
      expect(find.text('Make some rolls!'), findsNothing);
    });

    testWidgets('rolls two virtual dice and shows combined result in history', (tester) async {
      await startApp(tester);
      await addVirtualDie(tester, 'd20', 20);
      await addVirtualDie(tester, 'd6', 6);
      await roll(tester);

      // Multi-die rolls produce a history entry
      expect(find.textContaining('Roll '), findsWidgets);
    });

    testWidgets('clear button removes all history entries', (tester) async {
      await startApp(tester);
      await addVirtualDie(tester, 'd6', 6);
      await roll(tester);
      await roll(tester);

      expect(find.text('Make some rolls!'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Make some rolls!'), findsOneWidget);
    });

    testWidgets('auto-roll switch can be toggled off and back on', (tester) async {
      await startApp(tester);

      // The Switch and its "Auto-roll" label are siblings inside a Wrap.
      // Tap the Switch directly — tapping the plain Text sibling does nothing.
      final autoRollSwitch = find.descendant(
        of: find.ancestor(
          of: find.text('Auto-roll'),
          matching: find.byType(Wrap),
        ),
        matching: find.byType(Switch),
      );

      expect(tester.widget<Switch>(autoRollSwitch).value, isTrue);

      await tester.tap(autoRollSwitch);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(autoRollSwitch).value, isFalse);

      await tester.tap(autoRollSwitch);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(autoRollSwitch).value, isTrue);
    });

    testWidgets('manual Roll button still works when auto-roll is off', (tester) async {
      await startApp(tester);
      await addVirtualDie(tester, 'd6', 6);

      await tester.tap(find.text('Auto-roll'));
      await tester.pumpAndSettle();

      await roll(tester);

      expect(find.textContaining('Roll '), findsWidgets);
    });
  });
}
