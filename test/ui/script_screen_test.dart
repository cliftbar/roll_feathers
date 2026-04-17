import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';
import 'package:roll_feathers/ui/app_settings/script_screen.dart';

class MockAppSettingsScreenViewModel extends Mock implements AppSettingsScreenViewModel {}

void main() {
  late MockAppSettingsScreenViewModel mockViewModel;

  setUp(() {
    mockViewModel = MockAppSettingsScreenViewModel();
    // Default behaviors
    when(() => mockViewModel.getRuleScripts()).thenReturn([]);
    // mockViewModel is a ChangeNotifier, so we should make it one or mockaddListener
    // But since we use ListenableBuilder, it will call addListener.
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ScriptScreenWidget(viewModel: mockViewModel),
    );
  }

  testWidgets('Add script dialog does not have a name field', (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    // Open Add Script Dialog
    await tester.tap(find.text('New Script'));
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(find.text('Add New Script'), findsOneWidget);

    // Verify "Script Name" field is NOT present
    expect(find.text('Script Name'), findsNothing);
    expect(find.byType(TextField), findsOneWidget); // Only Content field

    // Verify "Script Content" field IS present
    expect(find.text('Script Content'), findsOneWidget);

    // Enter content and save
    await tester.enterText(find.byType(TextField), 'define myTest for roll *d*\n  use selection \$ALL_DICE\n    aggregate over selection sum\n    on result [*:*] action blink');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify addRuleScript was called with the content
    verify(() => mockViewModel.addRuleScript(any())).called(1);
  });

  testWidgets('Edit script dialog does not have a name field', (WidgetTester tester) async {
    final script = RuleScript(name: 'ExistingScript', script: 'define ExistingScript for roll *d*\n action blink', enabled: true);
    when(() => mockViewModel.getRuleScripts()).thenReturn([script]);

    await tester.pumpWidget(createWidgetUnderTest());

    // Open Edit Script Dialog
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(find.text('Edit Script'), findsOneWidget);

    // Verify "Script Name" field is NOT present
    expect(find.text('Script Name'), findsNothing);
    expect(find.byType(TextField), findsOneWidget); // Only Content field

    // Verify "Script Content" field IS present and has correct text
    expect(find.text('Script Content'), findsOneWidget);
    final textField = find.byType(TextField);
    expect(tester.widget<TextField>(textField).controller?.text, 'define ExistingScript for roll *d*\n action blink');

    // Enter new content and save
    await tester.enterText(find.byType(TextField), 'define UpdatedScript for roll *d*\n action blink');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify addRuleScript was called with the new content
    verify(() => mockViewModel.addRuleScript('define UpdatedScript for roll *d*\n action blink', enabled: true)).called(1);
  });
}
