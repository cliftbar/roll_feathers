import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

/// Layout tests across several viewport sizes to catch RenderFlex overflows.
/// A RenderFlex overflow in debug mode throws a FlutterError → test failure.
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

  // ---------------------------------------------------------------------------
  // 360×800 — narrow phone portrait (Galaxy S-class)
  // ---------------------------------------------------------------------------

  group('narrow screen layout (360×800)', () {
    setUp(() => setSize(const Size(360, 800)));
    tearDown(clearSize);

    testWidgets('home screen renders without overflow', (tester) async {
      await startApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('dddice unauthenticated dialog has no overflow', (tester) async {
      await startApp(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign in with dddice'), findsOneWidget);
      expect(find.text('Use guest account'), findsOneWidget);
    });

    testWidgets('dddice authenticated dialog has no overflow', (tester) async {
      await startAppWithGuestConfig(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('nav drawer renders without overflow', (tester) async {
      await startApp(tester);
      await openSettings(tester);
      expect(find.text('Rule Scripts'), findsOneWidget);
    });

    testWidgets('add die dialog renders without overflow', (tester) async {
      await startApp(tester);
      await tester.tap(find.text('Add Die'));
      // pumpAndSettle would block indefinitely: the cursor blink animation in
      // the dialog's TextFields never stops. One pump is enough to render the
      // layout and catch any RenderFlex overflow.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 800×360 — phone landscape (common at the gaming table)
  // ---------------------------------------------------------------------------

  group('landscape phone layout (800×360)', () {
    setUp(() => setSize(const Size(800, 360)));
    tearDown(clearSize);

    testWidgets('home screen renders without overflow', (tester) async {
      await startApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('dddice unauthenticated dialog has no overflow', (tester) async {
      await startApp(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign in with dddice'), findsOneWidget);
      expect(find.text('Use guest account'), findsOneWidget);
    });

    testWidgets('dddice authenticated dialog has no overflow', (tester) async {
      await startAppWithGuestConfig(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('add die dialog renders without overflow', (tester) async {
      await startApp(tester);
      await tester.tap(find.text('Add Die'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 728×900 — half-screen desktop (window snapped to half of 1440-wide monitor)
  // ---------------------------------------------------------------------------

  group('half-screen desktop layout (728×900)', () {
    setUp(() => setSize(const Size(728, 900)));
    tearDown(clearSize);

    testWidgets('home screen renders without overflow', (tester) async {
      await startApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('dddice unauthenticated dialog has no overflow', (tester) async {
      await startApp(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign in with dddice'), findsOneWidget);
      expect(find.text('Use guest account'), findsOneWidget);
    });

    testWidgets('dddice authenticated dialog has no overflow', (tester) async {
      await startAppWithGuestConfig(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('add die dialog renders without overflow', (tester) async {
      await startApp(tester);
      await tester.tap(find.text('Add Die'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 360×450 — quarter-screen / small snapped window
  // ---------------------------------------------------------------------------

  group('quarter-screen layout (360×450)', () {
    setUp(() => setSize(const Size(360, 450)));
    tearDown(clearSize);

    testWidgets('home screen renders without overflow', (tester) async {
      await startApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('dddice unauthenticated dialog has no overflow', (tester) async {
      await startApp(tester);
      await openDddiceSettings(tester);
      expect(find.text('Sign in with dddice'), findsOneWidget);
      expect(find.text('Use guest account'), findsOneWidget);
    });
  });
}
