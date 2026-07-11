import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

/// On-device coverage for the webhook payload editor's responsive layout:
/// Settings → Webhook Payloads → editor. Asserts the Edit/Preview tab split on a
/// narrow phone and the side-by-side editor+preview on a wide window, and (since
/// a RenderFlex overflow throws in debug) that neither shape overflows.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void setSize(Size size) {
    // ignore: deprecated_member_use
    TestWidgetsFlutterBinding.instance.window.physicalSizeTestValue = size;
    // ignore: deprecated_member_use
    TestWidgetsFlutterBinding.instance.window.devicePixelRatioTestValue = 1.0;
  }

  void clearSize() {
    // ignore: deprecated_member_use
    TestWidgetsFlutterBinding.instance.window.clearPhysicalSizeTestValue();
    // ignore: deprecated_member_use
    TestWidgetsFlutterBinding.instance.window.clearDevicePixelRatioTestValue();
  }

  Future<void> openPayloads(WidgetTester tester) async {
    await startApp(tester);
    await openSettingsItem(tester, 'Webhook Payloads');
  }

  /// Open a fresh, editable payload via the "New" FAB.
  Future<void> openNewEditor(WidgetTester tester) async {
    await openPayloads(tester);
    await tester.tap(find.text('New'));
    // No field is autofocused, so pumpAndSettle won't hang on a cursor blink.
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // 360×800 — narrow phone portrait: Edit/Preview tabs
  // ---------------------------------------------------------------------------

  group('webhook payloads — narrow phone (360×800)', () {
    setUp(() => setSize(const Size(360, 800)));
    tearDown(clearSize);

    testWidgets('payload list renders built-ins without overflow', (tester) async {
      await openPayloads(tester);
      expect(find.text('Built-in'), findsOneWidget);
      expect(find.text('Discord (Classic)'), findsOneWidget);
      expect(find.text('Generic JSON'), findsOneWidget);
    });

    testWidgets('editor opens as an Edit/Preview tab split', (tester) async {
      await openNewEditor(tester);

      // Tabbed layout on a narrow screen.
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Preview'), findsOneWidget);

      // Edit tab (default): the body editor is visible; the live preview lives
      // on the other tab, not here. (The variable palette sits below the fold in
      // the lazy Edit-tab list; its presence is covered by the wide-layout test
      // below and the editor widget tests.)
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('Preview (sample roll)'), findsNothing);

      // Switching to Preview reveals the live render.
      await tester.tap(find.widgetWithText(Tab, 'Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Preview (sample roll)'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 1000×800 — wide window: editor + preview side by side (no tabs)
  // ---------------------------------------------------------------------------

  group('webhook payloads — wide window (1000×800)', () {
    setUp(() => setSize(const Size(1000, 800)));
    tearDown(clearSize);

    testWidgets('editor shows body and live preview side by side, no tabs', (tester) async {
      await openNewEditor(tester);

      expect(find.byType(TabBar), findsNothing);
      // Both the body editor and the live preview are on screen at once.
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('Insert variable'), findsOneWidget);
      expect(find.text('Preview (sample roll)'), findsOneWidget);
    });
  });
}
