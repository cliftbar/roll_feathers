import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen_vm.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/util/command.dart';

class MockDiceScreenViewModel extends Mock implements DiceScreenViewModel {}
class MockAppSettingsScreenViewModel extends Mock implements AppSettingsScreenViewModel {}

void main() {
  late MockDiceScreenViewModel mockDiceVm;
  late MockAppSettingsScreenViewModel mockSettingsVm;

  setUp(() {
    mockDiceVm = MockDiceScreenViewModel();
    mockSettingsVm = MockAppSettingsScreenViewModel();

    when(() => mockDiceVm.getDeviceStream()).thenAnswer((_) => Stream.value({}));
    when(() => mockDiceVm.getResultsStream()).thenAnswer((_) => Stream.value([]));
    when(() => mockDiceVm.dice).thenReturn({});
    when(() => mockDiceVm.rollHistory).thenReturn([]);
    
    when(() => mockSettingsVm.bleIsEnabled()).thenReturn(true);
    when(() => mockSettingsVm.isScanning).thenReturn(false);
    when(() => mockSettingsVm.themeMode).thenReturn(ThemeMode.light);
    when(() => mockSettingsVm.getHaConfig()).thenReturn(const HaConfig(enabled: false, url: '', token: '', entity: ''));
    when(() => mockSettingsVm.dicePaneOrientation).thenReturn(DicePaneOrientation.auto);
    when(() => mockSettingsVm.getIpAddresses()).thenReturn([]);
    when(() => mockSettingsVm.getDddiceConfig()).thenReturn(const DddiceConfig());
    when(() => mockSettingsVm.webhooksEnabled).thenReturn(false);
    when(() => mockSettingsVm.getKeepScreenOn()).thenReturn(false);
    when(() => mockSettingsVm.addListener(any())).thenReturn(null);
    when(() => mockSettingsVm.removeListener(any())).thenReturn(null);
    
    // Commands in DiceScreenViewModel (needed for the build method)
    // rollAllVirtualDice is used in TextButton.icon
    // disconnectAllDice is used in ListTile (Drawer)
    // removeAllVirtualDice is used in ListTile (Drawer)
  });

  Widget pumpTestWidget() {
    return MaterialApp(
      home: DiceScreenWidget(
        viewModel: mockDiceVm,
        settingsVm: mockSettingsVm,
        appVersion: '0.0.0',
      ),
    );
  }

  testWidgets('should not overflow on narrow screen widths', (tester) async {
    // macOS window can be resized very small.
    // Setting a very narrow width to verify responsive layout.
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(pumpTestWidget());
    
    expect(tester.takeException(), isNull);
  });

  testWidgets('should not overflow on extremely narrow screen widths (forcing column)', (tester) async {
    tester.view.physicalSize = const Size(200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(pumpTestWidget());
    
    expect(tester.takeException(), isNull);
  });

  testWidgets('should not overflow on short screen heights (narrow)', (tester) async {
    // Android split-view can make the screen very short.
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(pumpTestWidget());
    
    expect(tester.takeException(), isNull);
  });
  testWidgets('should not overflow on extremely small screens (200x200)', (tester) async {
    tester.view.physicalSize = const Size(200, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(pumpTestWidget());
    
    expect(tester.takeException(), isNull);
  });

  testWidgets('should respect forced vertical orientation on wide screen', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    when(() => mockSettingsVm.dicePaneOrientation).thenReturn(DicePaneOrientation.vertical);

    await tester.pumpWidget(pumpTestWidget());

    expect(find.byKey(const Key('dice_screen_vertical_layout')), findsOneWidget);
    expect(find.byKey(const Key('dice_screen_horizontal_layout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('should respect forced horizontal orientation on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    when(() => mockSettingsVm.dicePaneOrientation).thenReturn(DicePaneOrientation.horizontal);

    await tester.pumpWidget(pumpTestWidget());

    expect(find.byKey(const Key('dice_screen_horizontal_layout')), findsOneWidget);
    expect(find.byKey(const Key('dice_screen_vertical_layout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('should respect auto orientation (horizontal on wide)', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    when(() => mockSettingsVm.dicePaneOrientation).thenReturn(DicePaneOrientation.auto);

    await tester.pumpWidget(pumpTestWidget());

    expect(find.byKey(const Key('dice_screen_horizontal_layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('should respect auto orientation (vertical on narrow)', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    when(() => mockSettingsVm.dicePaneOrientation).thenReturn(DicePaneOrientation.auto);

    await tester.pumpWidget(pumpTestWidget());

    expect(find.byKey(const Key('dice_screen_vertical_layout')), findsOneWidget);
    expect(find.byKey(const Key('dice_screen_horizontal_layout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('should respect forced vertical + short screen (compact layout)', (tester) async {
    tester.view.physicalSize = const Size(1000, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    when(() => mockSettingsVm.dicePaneOrientation).thenReturn(DicePaneOrientation.vertical);

    await tester.pumpWidget(pumpTestWidget());

    expect(find.byKey(const Key('dice_screen_compact_layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Empty state ────────────────────────────────────────────────────────────

  testWidgets('empty dice list shows CTA with add instructions', (tester) async {
    await tester.pumpWidget(pumpTestWidget());
    expect(find.textContaining('Tap Add Die'), findsOneWidget);
  });

  // ── Drawer confirmation dialogs ────────────────────────────────────────────

  group('drawer confirmation dialogs', () {
    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      // Scroll the drawer ListView until the dice-management tiles are visible.
      await tester.scrollUntilVisible(find.text('Remove Virtual Dice'), 50.0);
      await tester.pumpAndSettle();
    }

    testWidgets('Remove Virtual Dice shows confirmation dialog', (tester) async {
      await tester.pumpWidget(pumpTestWidget());
      await openDrawer(tester);

      await tester.tap(find.text('Remove Virtual Dice'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Virtual Dice'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('Remove Virtual Dice cancel dismisses without executing', (tester) async {
      bool executed = false;
      when(() => mockDiceVm.removeAllVirtualDice).thenReturn(
        Command0(() async { executed = true; return Result.value(null); }),
      );

      await tester.pumpWidget(pumpTestWidget());
      await openDrawer(tester);
      await tester.tap(find.text('Remove Virtual Dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(executed, isFalse);
    });

    testWidgets('Remove Virtual Dice confirm executes the command', (tester) async {
      bool executed = false;
      when(() => mockDiceVm.removeAllVirtualDice).thenReturn(
        Command0(() async { executed = true; return Result.value(null); }),
      );

      await tester.pumpWidget(pumpTestWidget());
      await openDrawer(tester);
      await tester.tap(find.text('Remove Virtual Dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(executed, isTrue);
    });

    testWidgets('Remove All Dice shows confirmation dialog', (tester) async {
      await tester.pumpWidget(pumpTestWidget());
      await openDrawer(tester);

      await tester.tap(find.text('Remove All Dice'));
      await tester.pumpAndSettle();

      expect(find.text('Remove All Dice'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('Remove All Dice confirm executes the command', (tester) async {
      bool executed = false;
      when(() => mockDiceVm.disconnectAllDice).thenReturn(
        Command0(() async { executed = true; return Result.value(null); }),
      );

      await tester.pumpWidget(pumpTestWidget());
      await openDrawer(tester);
      await tester.tap(find.text('Remove All Dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(executed, isTrue);
    });
  });

  // ── Roll history display name ──────────────────────────────────────────────

  testWidgets('roll history uses ruleDisplayName when set', (tester) async {
    final roll = RollResult(
      rollType: RollType.rule,
      rollResult: 15,
      rolls: {'die-1': 15},
      ruleName: 'standardRoll',
      ruleDisplayName: 'Basic Blink',
    );
    when(() => mockDiceVm.rollHistory).thenReturn([roll]);
    when(() => mockDiceVm.getResultsStream()).thenAnswer((_) => Stream.value([roll]));
    when(() => mockDiceVm.getDieById(any())).thenReturn(null);

    await tester.pumpWidget(pumpTestWidget());
    await tester.pumpAndSettle();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plain = richTexts.map((w) => w.text.toPlainText()).join(' ');
    expect(plain, contains('Basic Blink'));
    expect(plain, isNot(contains('standardRoll')));
  });

  testWidgets('roll history falls back to ruleName when no displayName', (tester) async {
    final roll = RollResult(
      rollType: RollType.rule,
      rollResult: 15,
      rolls: {'die-1': 15},
      ruleName: 'standardRoll',
    );
    when(() => mockDiceVm.rollHistory).thenReturn([roll]);
    when(() => mockDiceVm.getResultsStream()).thenAnswer((_) => Stream.value([roll]));
    when(() => mockDiceVm.getDieById(any())).thenReturn(null);

    await tester.pumpWidget(pumpTestWidget());
    await tester.pumpAndSettle();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plain = richTexts.map((w) => w.text.toPlainText()).join(' ');
    expect(plain, contains('standardRoll'));
  });
}
