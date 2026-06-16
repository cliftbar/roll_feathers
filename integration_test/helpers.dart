import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// Run tests with --dart-define=INTEGRATION_TEST=true so DI uses NoopBleRepository
// (skips Bluetooth init and avoids the macOS/iOS permission dialog).
import 'package:roll_feathers/main.dart' as app;

/// Clear all storage and launch a fresh app instance.
Future<void> startApp(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  await tester.runAsync(() async => app.main());
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// Seed a dddice guest session then launch the app. Mirrors the localStorage
/// injection used in the Playwright beforeEach blocks.
Future<void> startAppWithGuestConfig(
  WidgetTester tester, {
  String token = 'test-guest-token',
  String roomSlug = 'test-room',
  String roomName = 'Test Room',
  bool enabled = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final asyncPrefs = SharedPreferencesAsync();
  await asyncPrefs.setString('dddice_token', token);
  await asyncPrefs.setBool('dddice_is_guest', true);
  await asyncPrefs.setBool('dddice_enabled', enabled);
  await asyncPrefs.setBool('dddice_needs_reauth', false);
  await asyncPrefs.setString('dddice_room_slug', roomSlug);
  await asyncPrefs.setString('dddice_room_name', roomName);
  await asyncPrefs.setString('dddice_theme_id', '');
  await asyncPrefs.setString('dddice_theme_name', '');

  await tester.runAsync(() async => app.main());
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// Add a virtual die via the Add Die dialog.
Future<void> addVirtualDie(WidgetTester tester, String name, int faces) async {
  await tester.tap(find.text('Add Die'));
  await tester.pumpAndSettle();

  // Dialog has two TextFields in order: Die Name, Number of Faces
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), faces.toString());

  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
}

/// Tap the Roll button and settle animations.
Future<void> roll(WidgetTester tester) async {
  await tester.tap(find.text('Roll'));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Open the navigation drawer.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

/// Open the nav drawer and tap a settings item by label text.
Future<void> openSettingsItem(WidgetTester tester, String label) async {
  await openSettings(tester);
  await _scrollDrawerToItem(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Scrolls the open Drawer's ListView until [item] is within the viewport.
Future<void> _scrollDrawerToItem(WidgetTester tester, Finder item) async {
  final drawerScrollable = find.descendant(
    of: find.byType(Drawer),
    matching: find.byType(Scrollable),
  );
  if (drawerScrollable.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(item, 200.0, scrollable: drawerScrollable);
  await tester.pumpAndSettle();
}

/// Tap the dddice Settings nav item to open the dddice dialog.
Future<void> openDddiceSettings(WidgetTester tester) async {
  // The nav item label starts with 'dddice Settings'
  await openSettings(tester);
  // On narrow screens the drawer ListView may need to scroll to reveal the item.
  await _scrollDrawerToItem(tester, find.textContaining('dddice Settings'));
  await tester.tap(find.textContaining('dddice Settings'));
  await tester.pumpAndSettle();
}

/// Close the dddice dialog.
Future<void> closeDddiceDialog(WidgetTester tester) async {
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
}

/// Returns true if any visible Text widget contains [text].
bool hasText(WidgetTester tester, String text) =>
    find.textContaining(text).evaluate().isNotEmpty;

/// Returns the number of history entries currently visible.
int historyEntryCount(WidgetTester tester) =>
    find.textContaining('Roll ').evaluate().length;
