import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';
import 'package:roll_feathers/ui/app_settings/script_screen.dart';

class MockAppSettingsScreenViewModel extends Mock implements AppSettingsScreenViewModel {}

const String _validScript = '''
define myTest for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
''';

void main() {
  late MockAppSettingsScreenViewModel mockViewModel;

  setUp(() {
    mockViewModel = MockAppSettingsScreenViewModel();
    when(() => mockViewModel.getRuleScripts()).thenReturn([]);
    when(() => mockViewModel.saveError).thenReturn(null);
    when(() => mockViewModel.getHiddenDefaultRules()).thenReturn([]);
    when(() => mockViewModel.isUserOnlyRule(any())).thenReturn(false);
    when(() => mockViewModel.addRuleScript(any())).thenAnswer((_) async {});
    when(() => mockViewModel.addRuleScript(any(), enabled: any(named: 'enabled')))
        .thenAnswer((_) async {});
    when(() => mockViewModel.toggleRuleScript(any(), any())).thenAnswer((_) async {});
    when(() => mockViewModel.reorderRules(any(), any())).thenAnswer((_) async {});
    when(() => mockViewModel.removeRule(any())).thenAnswer((_) async {});
    when(() => mockViewModel.unhideRule(any())).thenAnswer((_) async {});
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ScriptScreenWidget(viewModel: mockViewModel),
    );
  }

  testWidgets('Add script dialog does not have a name field', (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    await tester.tap(find.text('New Script'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Script'), findsOneWidget);
    expect(find.text('Script Name'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Script Content'), findsOneWidget);

    await tester.enterText(find.byType(TextField), _validScript);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockViewModel.addRuleScript(any())).called(1);
  });

  testWidgets('Edit script dialog does not have a name field', (WidgetTester tester) async {
    final script = RuleScript(
      name: 'ExistingScript',
      script: 'define ExistingScript for roll *d*\n action blink',
      enabled: true,
    );
    when(() => mockViewModel.getRuleScripts()).thenReturn([script]);
    when(() => mockViewModel.isUserOnlyRule('ExistingScript')).thenReturn(true);

    await tester.pumpWidget(createWidgetUnderTest());

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    expect(find.text('Edit Script'), findsOneWidget);
    expect(find.text('Script Name'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Script Content'), findsOneWidget);
    final textField = find.byType(TextField);
    expect(
      tester.widget<TextField>(textField).controller?.text,
      'define ExistingScript for roll *d*\n action blink',
    );

    await tester.enterText(find.byType(TextField), 'define UpdatedScript for roll *d*\n action blink');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockViewModel.addRuleScript(
      'define UpdatedScript for roll *d*\n action blink',
      enabled: true,
    )).called(1);
  });

  testWidgets('invalid DSL in add dialog → inline error text shown, dialog stays open', (WidgetTester tester) async {
    // Simulate addRuleScript setting saveError (parse failure)
    when(() => mockViewModel.addRuleScript(any())).thenAnswer((_) async {
      when(() => mockViewModel.saveError).thenReturn('FormatException: invalid DSL');
    });

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.tap(find.text('New Script'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bad dsl');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Dialog must still be open (not popped) and error must be visible
    expect(find.text('Add New Script'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsOneWidget);
  });

  testWidgets('star icon shown for user-only rules, not for defaults', (WidgetTester tester) async {
    final userRule = RuleScript(name: 'myCustom', script: _validScript, enabled: true);
    final defaultRule = RuleScript(name: 'Basic Blink', script: standardRoll, enabled: true);
    when(() => mockViewModel.getRuleScripts()).thenReturn([userRule, defaultRule]);
    when(() => mockViewModel.isUserOnlyRule('myCustom')).thenReturn(true);
    when(() => mockViewModel.isUserOnlyRule('Basic Blink')).thenReturn(false);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('hidden rules section shown when getHiddenDefaultRules() is non-empty', (WidgetTester tester) async {
    final hiddenRule = RuleScript(name: 'Basic Blink', script: standardRoll, enabled: true);
    when(() => mockViewModel.getHiddenDefaultRules()).thenReturn([hiddenRule]);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('1 hidden rule'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('Restore button triggers unhideRule on VM', (WidgetTester tester) async {
    final hiddenRule = RuleScript(name: 'Basic Blink', script: standardRoll, enabled: true);
    when(() => mockViewModel.getHiddenDefaultRules()).thenReturn([hiddenRule]);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    verify(() => mockViewModel.unhideRule('Basic Blink')).called(1);
  });
}
