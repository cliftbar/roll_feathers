import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen_vm.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';

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
    
    // Commands in DiceScreenViewModel (needed for the build method)
    // rollAllVirtualDice is used in TextButton.icon
    // disconnectAllDice is used in ListTile (Drawer)
    // removeAllVirtualDice is used in ListTile (Drawer)
  });

  Widget _pumpTestWidget() {
    return MaterialApp(
      home: DiceScreenWidget(
        viewModel: mockDiceVm,
        settingsVm: mockSettingsVm,
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

    await tester.pumpWidget(_pumpTestWidget());
    
    expect(tester.takeException(), isNull);
  });

  testWidgets('should not overflow on extremely narrow screen widths (forcing column)', (tester) async {
    tester.view.physicalSize = const Size(200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_pumpTestWidget());
    
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

    await tester.pumpWidget(_pumpTestWidget());
    
    expect(tester.takeException(), isNull);
  });
  testWidgets('should not overflow on extremely small screens (200x200)', (tester) async {
    tester.view.physicalSize = const Size(200, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_pumpTestWidget());
    
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

    await tester.pumpWidget(_pumpTestWidget());

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

    await tester.pumpWidget(_pumpTestWidget());

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

    await tester.pumpWidget(_pumpTestWidget());

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

    await tester.pumpWidget(_pumpTestWidget());

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

    await tester.pumpWidget(_pumpTestWidget());

    expect(find.byKey(const Key('dice_screen_compact_layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
