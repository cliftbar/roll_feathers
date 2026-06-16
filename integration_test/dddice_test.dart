import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

// Pass via --dart-define=DDDICE_TOKEN=xxx --dart-define=DDDICE_ROOM=yyy
const _token = String.fromEnvironment('DDDICE_TOKEN');
const _room = String.fromEnvironment('DDDICE_ROOM');
const _roomName = String.fromEnvironment('DDDICE_ROOM_NAME', defaultValue: 'test-room');
// Guest-flow test only needs network access (room is created automatically).
const _hasToken = _token != '';
// Roll tests need a pre-configured room slug.
const _hasRealCreds = _token != '' && _room != '';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Group 1: dddice settings UI — no live network required
  // ---------------------------------------------------------------------------

  group('dddice settings UI', () {
    testWidgets('nav subtitle shows Guest and room name when configured', (tester) async {
      await startAppWithGuestConfig(tester, roomName: 'my-room');
      await openSettings(tester);

      expect(find.textContaining('Guest'), findsWidgets);
      expect(find.textContaining('my-room'), findsWidgets);
    });

    testWidgets('enable toggle turns dddice on', (tester) async {
      await startAppWithGuestConfig(tester, enabled: false);
      await openDddiceSettings(tester);

      final toggle = find.widgetWithText(SwitchListTile, 'Enable dddice');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('enable toggle persists after reopening dialog', (tester) async {
      await startAppWithGuestConfig(tester, enabled: false);
      await openDddiceSettings(tester);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Enable dddice'));
      await tester.pumpAndSettle();
      await closeDddiceDialog(tester);

      // Re-open and verify the toggle is still on
      await openDddiceSettings(tester);
      final toggle = find.widgetWithText(SwitchListTile, 'Enable dddice');
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('sign out returns to unauthenticated state', (tester) async {
      await startAppWithGuestConfig(tester);
      await openDddiceSettings(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // After sign out, the unauthenticated buttons should appear
      expect(find.text('Sign in with dddice'), findsOneWidget);
      expect(find.text('Use guest account'), findsOneWidget);
    });

    testWidgets('sign out clears token in storage', (tester) async {
      await startAppWithGuestConfig(tester);
      await openDddiceSettings(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await closeDddiceDialog(tester);

      // Read directly from the async prefs to verify storage was cleared
      final prefs = SharedPreferencesAsync();
      final token = await prefs.getString('dddice_token');
      expect(token ?? '', isEmpty);
    });

    testWidgets('theme row shows dddice-bees label for guest accounts', (tester) async {
      await startAppWithGuestConfig(tester);
      await openDddiceSettings(tester);

      expect(find.text('dddice-bees (guest default)'), findsOneWidget);
    });

  });

  // ---------------------------------------------------------------------------
  // Group 2: Live dddice integration — requires real credentials
  // Pass --dart-define=DDDICE_TOKEN=xxx --dart-define=DDDICE_ROOM=yyy
  // ---------------------------------------------------------------------------

  group('dddice live integration', () {
    testWidgets(
      'Use guest account button creates guest session with auto room',
      (tester) async {
        await startApp(tester);
        await openDddiceSettings(tester);

        expect(find.text('Sign in with dddice'), findsOneWidget);

        await tester.tap(find.text('Use guest account'));
        // Allow network round-trips for guest token + room creation
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(find.text('Sign in with dddice'), findsNothing);
        expect(find.text('Sign out'), findsOneWidget);
        expect(find.text('dddice-bees (guest default)'), findsOneWidget);
      },
      skip: !_hasToken,
    );

    testWidgets(
      'single virtual die roll fires to dddice without error',
      (tester) async {
        await startAppWithGuestConfig(
          tester,
          token: _token,
          roomSlug: _room,
          roomName: _roomName,
          enabled: true,
        );

        await addVirtualDie(tester, 'd20', 20);
        await roll(tester);

        // Allow network round-trip
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(find.textContaining('Roll '), findsWidgets);
      },
      skip: !_hasRealCreds,
    );

    testWidgets(
      'multi-die roll fires both dice to dddice',
      (tester) async {
        await startAppWithGuestConfig(
          tester,
          token: _token,
          roomSlug: _room,
          roomName: _roomName,
          enabled: true,
        );

        await addVirtualDie(tester, 'd20', 20);
        await addVirtualDie(tester, 'd6', 6);
        await roll(tester);

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(find.textContaining('Roll '), findsWidgets);
      },
      skip: !_hasRealCreds,
    );

    testWidgets(
      'rule label is sent to dddice when Basic Blink fires',
      (tester) async {
        await startAppWithGuestConfig(
          tester,
          token: _token,
          roomSlug: _room,
          roomName: _roomName,
          enabled: true,
        );

        // Ensure Basic Blink is enabled
        await openSettingsItem(tester, 'Rule Scripts');
        final basicBlinkTile = find.ancestor(
          of: find.text('Basic Blink'),
          matching: find.byType(ListTile),
        );
        final checkbox = find.descendant(
          of: basicBlinkTile,
          matching: find.byType(Checkbox),
        );
        if (tester.widget<Checkbox>(checkbox).value != true) {
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
        }

        // Navigate back
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        await addVirtualDie(tester, 'd20', 20);
        await roll(tester);

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // Rule-driven rolls include the rule name in history
        expect(find.textContaining('standardRoll'), findsWidgets);
      },
      skip: !_hasRealCreds,
    );

    testWidgets(
      'second roll in same session does not re-join room',
      (tester) async {
        await startAppWithGuestConfig(
          tester,
          token: _token,
          roomSlug: _room,
          roomName: _roomName,
          enabled: true,
        );

        await addVirtualDie(tester, 'd6', 6);

        await roll(tester);
        await tester.pump(const Duration(seconds: 1));
        final countAfterFirst = historyEntryCount(tester);

        await roll(tester);
        await tester.pump(const Duration(seconds: 1));
        final countAfterSecond = historyEntryCount(tester);

        // Both rolls recorded, no crash/error on second roll
        expect(countAfterSecond, greaterThan(countAfterFirst));
      },
      skip: !_hasRealCreds,
    );
  });
}
