import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';

class _FailingAppService extends InMemoryAppService {
  bool failOnNextWrite = false;

  @override
  Future<void> setSavedScripts(List<String> rules) async {
    if (failOnNextWrite) {
      failOnNextWrite = false;
      throw Exception('disk full');
    }
    return super.setSavedScripts(rules);
  }

  @override
  Future<void> setRuleOrder(List<String> order) async {
    if (failOnNextWrite) {
      failOnNextWrite = false;
      throw Exception('disk full');
    }
    return super.setRuleOrder(order);
  }
}

const String _validScript = '''
define myTest for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
''';

const String _validScript2 = '''
define myOther for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
''';

Future<(AppSettingsScreenViewModel, _FailingAppService)> _buildVm() async {
  final app = _FailingAppService();
  final dd = RecordingDieDomain();
  final wd = WebhookDomain(appService: app);
  final ruleParser = RuleEvaluator(dd, app, wd);
  await ruleParser.init();
  final di = await DiWrapper.forTesting(
    appService: app,
    dieDomain: dd,
    ruleParser: ruleParser,
    webhookDomain: wd,
  );
  final vm = AppSettingsScreenViewModel(di);
  return (vm, app);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('VM rule methods', () {
    testWidgets('addRuleScript success → saveError is null, rules updated', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      await vm.addRuleScript(_validScript);

      expect(vm.saveError, isNull);
      expect(vm.getRuleScripts().any((r) => r.name == 'myTest'), isTrue);
    });

    testWidgets('addRuleScript invalid DSL → saveError set, getRuleScripts unchanged', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      final before = vm.getRuleScripts().map((r) => r.name).toList();
      await vm.addRuleScript('not valid DSL at all');

      expect(vm.saveError, isNotNull);
      final after = vm.getRuleScripts().map((r) => r.name).toList();
      expect(after, equals(before));
    });

    testWidgets('addRuleScript persistence failure → saveError set, state unchanged', (tester) async {
      final (vm, app) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      final before = vm.getRuleScripts().map((r) => r.name).toList();
      app.failOnNextWrite = true;
      await vm.addRuleScript(_validScript);

      expect(vm.saveError, isNotNull);
      final after = vm.getRuleScripts().map((r) => r.name).toList();
      expect(after, equals(before));
    });

    testWidgets('removeRule on default → getHiddenDefaultRules() non-empty', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      final scripts = vm.getRuleScripts();
      final defaultIdx = scripts.length - 1;
      await vm.removeRule(defaultIdx);

      expect(vm.getHiddenDefaultRules(), isNotEmpty);
    });

    testWidgets('unhideRule → getHiddenDefaultRules() no longer contains rule', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      final scripts = vm.getRuleScripts();
      final defaultIdx = scripts.length - 1;
      final defaultName = scripts[defaultIdx].name;
      await vm.removeRule(defaultIdx);
      await vm.unhideRule(defaultName);

      expect(vm.getHiddenDefaultRules().any((r) => r.name == defaultName), isFalse);
    });

    testWidgets('notifyListeners called after await completes, not before', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      int notificationCount = 0;
      vm.addListener(() => notificationCount++);

      final future = vm.addRuleScript(_validScript);
      // Before the future resolves, listener has not been called yet
      expect(notificationCount, equals(0));
      await future;
      expect(notificationCount, greaterThan(0));
    });

    testWidgets('toggleRuleScript success → saveError null, enabled updated', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      await vm.addRuleScript(_validScript);
      final before = vm.getRuleScripts().firstWhere((r) => r.name == 'myTest').enabled;
      await vm.toggleRuleScript('myTest', !before);

      expect(vm.saveError, isNull);
      final after = vm.getRuleScripts().firstWhere((r) => r.name == 'myTest').enabled;
      expect(after, equals(!before));
    });

    testWidgets('reorderRules success → saveError null, order updated', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      await vm.addRuleScript(_validScript);
      await vm.addRuleScript(_validScript2);
      final firstName = vm.getRuleScripts().first.name;
      await vm.reorderRules(0, 1);

      expect(vm.saveError, isNull);
      expect(vm.getRuleScripts()[1].name, equals(firstName));
    });

    testWidgets('saveError cleared on subsequent successful call', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      await vm.addRuleScript('not valid DSL');
      expect(vm.saveError, isNotNull);

      await vm.addRuleScript(_validScript);
      expect(vm.saveError, isNull);
    });

    testWidgets('removeRule user-only rule → permanently removed, not in hidden', (tester) async {
      final (vm, _) = await _buildVm();
      addTearDown(vm.dispose);
      await tester.pumpAndSettle();

      await vm.addRuleScript(_validScript);
      final idx = vm.getRuleScripts().indexWhere((r) => r.name == 'myTest');
      await vm.removeRule(idx);

      expect(vm.getRuleScripts().any((r) => r.name == 'myTest'), isFalse);
      expect(vm.getHiddenDefaultRules().any((r) => r.name == 'myTest'), isFalse);
    });
  });
}
