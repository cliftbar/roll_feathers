import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/services/app_service.dart';

// Subclass of InMemoryAppService that can be told to fail on the next write.
class _FailingAppService extends InMemoryAppService {
  bool failOnNextWrite = false;

  @override
  Future<void> setSavedScripts(List<String> rules) async {
    if (failOnNextWrite) {
      failOnNextWrite = false;
      throw Exception('simulated persistence failure');
    }
    return super.setSavedScripts(rules);
  }

  @override
  Future<void> setRuleOrder(List<String> order) async {
    if (failOnNextWrite) {
      failOnNextWrite = false;
      throw Exception('simulated persistence failure');
    }
    return super.setRuleOrder(order);
  }

  @override
  Future<void> setHiddenRuleNames(List<String> names) async {
    if (failOnNextWrite) {
      failOnNextWrite = false;
      throw Exception('simulated persistence failure');
    }
    return super.setHiddenRuleNames(names);
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

Future<RuleEvaluator> _makeEvaluator(AppService app) async {
  final dd = RecordingDieDomain();
  final wd = WebhookDomain(appService: app);
  final ev = RuleEvaluator(dd, app, wd);
  await ev.init();
  return ev;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rule persistence', () {
    late _FailingAppService app;
    late RuleEvaluator ev;

    setUp(() async {
      app = _FailingAppService();
      ev = await _makeEvaluator(app);
    });

    test('addRuleScript valid → appears in getRules()', () async {
      await ev.addRuleScript(_validScript);
      expect(ev.getRules().any((r) => r.name == 'myTest'), isTrue);
    });

    test('addRuleScript invalid DSL → throws FormatException', () async {
      await expectLater(
        ev.addRuleScript('this is not valid DSL'),
        throwsA(isA<FormatException>()),
      );
    });

    test('addRuleScript new rule → appears at index 0', () async {
      await ev.addRuleScript(_validScript);
      expect(ev.getRules().first.name, equals('myTest'));
    });

    test('addRuleScript same name → replaced, no duplicate', () async {
      await ev.addRuleScript(_validScript);
      await ev.addRuleScript(_validScript);
      final matches = ev.getRules().where((r) => r.name == 'myTest');
      expect(matches.length, equals(1));
    });

    test('addRuleScript renamed define → new rule added, old still present', () async {
      await ev.addRuleScript(_validScript);
      final renamed = _validScript.replaceFirst('myTest', 'myTestRenamed');
      await ev.addRuleScript(renamed);
      final names = ev.getRules().map((r) => r.name).toList();
      expect(names, containsAll(['myTest', 'myTestRenamed']));
    });

    test('removeRule user-only rule → permanently removed', () async {
      await ev.addRuleScript(_validScript);
      final idx = ev.getRules().indexWhere((r) => r.name == 'myTest');
      await ev.removeRule(idx);
      expect(ev.getRules().any((r) => r.name == 'myTest'), isFalse);
    });

    test('removeRule default rule → hidden from getRules(), still in defaultRules', () async {
      final defaultName = defaultRules.first.name;
      final idx = ev.getRules().indexWhere((r) => r.name == defaultName);
      await ev.removeRule(idx);
      expect(ev.getRules().any((r) => r.name == defaultName), isFalse);
      expect(defaultRules.any((r) => r.name == defaultName), isTrue);
    });

    test('removeRule default rule → hidden state persists across reinit', () async {
      final defaultName = defaultRules.first.name;
      final idx = ev.getRules().indexWhere((r) => r.name == defaultName);
      await ev.removeRule(idx);

      final ev2 = await _makeEvaluator(app);
      expect(ev2.getRules().any((r) => r.name == defaultName), isFalse);
    });

    test('unhideRule → hidden default reappears in getRules()', () async {
      final defaultName = defaultRules.first.name;
      final idx = ev.getRules().indexWhere((r) => r.name == defaultName);
      await ev.removeRule(idx);
      await ev.unhideRule(defaultName);
      expect(ev.getRules().any((r) => r.name == defaultName), isTrue);
    });

    test('getHiddenDefaultRules → returns hidden defaults', () async {
      final defaultName = defaultRules.first.name;
      final idx = ev.getRules().indexWhere((r) => r.name == defaultName);
      await ev.removeRule(idx);
      final hidden = ev.getHiddenDefaultRules();
      expect(hidden.any((r) => r.name == defaultName), isTrue);
    });

    test('removeRule out-of-range index → no crash', () async {
      await expectLater(ev.removeRule(-1), completes);
      await expectLater(ev.removeRule(9999), completes);
    });

    test('reorderRules → new order reflected in getRules()', () async {
      await ev.addRuleScript(_validScript);
      await ev.addRuleScript(_validScript2);
      final before = ev.getRules().map((r) => r.name).toList();
      // swap first two
      await ev.reorderRules(0, 1);
      final after = ev.getRules().map((r) => r.name).toList();
      expect(after[0], equals(before[1]));
      expect(after[1], equals(before[0]));
    });

    test('toggleRuleScript on default → creates user override with new enabled state', () async {
      final defaultRule = defaultRules.first;
      final wasEnabled = defaultRule.enabled;
      await ev.toggleRuleScript(defaultRule.name, !wasEnabled);
      final found = ev.getRules().firstWhere((r) => r.name == defaultRule.name);
      expect(found.enabled, equals(!wasEnabled));
    });

    test('persistence failure in addRuleScript → state rolled back', () async {
      final before = ev.getRules().map((r) => r.name).toList();
      app.failOnNextWrite = true;
      await expectLater(
        ev.addRuleScript(_validScript),
        throwsA(isA<Exception>()),
      );
      final after = ev.getRules().map((r) => r.name).toList();
      expect(after, equals(before));
    });

    test('persistence failure in removeRule → state rolled back', () async {
      await ev.addRuleScript(_validScript);
      final before = ev.getRules().map((r) => r.name).toList();
      app.failOnNextWrite = true;
      final idx = ev.getRules().indexWhere((r) => r.name == 'myTest');
      await expectLater(ev.removeRule(idx), throwsA(isA<Exception>()));
      final after = ev.getRules().map((r) => r.name).toList();
      expect(after, equals(before));
    });

    test('isUserOnlyRule → true for user rule, false for default', () async {
      await ev.addRuleScript(_validScript);
      expect(ev.isUserOnlyRule('myTest'), isTrue);
      expect(ev.isUserOnlyRule(defaultRules.first.name), isFalse);
    });

    test('toggleRuleScript on user rule → updates enabled in place', () async {
      await ev.addRuleScript(_validScript); // enabled = true by default
      await ev.toggleRuleScript('myTest', false);
      final found = ev.getRules().firstWhere((r) => r.name == 'myTest');
      expect(found.enabled, isFalse);
    });

    test('persistence failure in toggleRuleScript → state rolled back', () async {
      await ev.addRuleScript(_validScript);
      final before = ev.getRules().map((r) => '${r.name}:${r.enabled}').toList();
      app.failOnNextWrite = true;
      await expectLater(
        ev.toggleRuleScript('myTest', false),
        throwsA(isA<Exception>()),
      );
      final after = ev.getRules().map((r) => '${r.name}:${r.enabled}').toList();
      expect(after, equals(before));
    });

    test('getRules(enabledOnly: true) → disabled rules excluded', () async {
      await ev.addRuleScript(_validScript);
      await ev.toggleRuleScript('myTest', false);
      final all = ev.getRules();
      final enabled = ev.getRules(enabledOnly: true);
      expect(all.any((r) => r.name == 'myTest'), isTrue);
      expect(enabled.any((r) => r.name == 'myTest'), isFalse);
    });

    test('persistence failure in reorderRules → state rolled back', () async {
      await ev.addRuleScript(_validScript);
      await ev.addRuleScript(_validScript2);
      final before = ev.getRules().map((r) => r.name).toList();
      app.failOnNextWrite = true;
      await expectLater(
        ev.reorderRules(0, 1),
        throwsA(isA<Exception>()),
      );
      final after = ev.getRules().map((r) => r.name).toList();
      expect(after, equals(before));
    });

    test('unhideRule on non-hidden name → no-op, getRules unchanged', () async {
      final before = ev.getRules().map((r) => r.name).toList();
      await ev.unhideRule('notHiddenAtAll');
      final after = ev.getRules().map((r) => r.name).toList();
      expect(after, equals(before));
    });

    test('unhideRule persists across reinit', () async {
      final defaultName = defaultRules.first.name;
      final idx = ev.getRules().indexWhere((r) => r.name == defaultName);
      await ev.removeRule(idx);
      await ev.unhideRule(defaultName);

      final ev2 = await _makeEvaluator(app);
      expect(ev2.getRules().any((r) => r.name == defaultName), isTrue);
    });

    test('persistence failure in unhideRule → state rolled back', () async {
      final defaultName = defaultRules.first.name;
      final idx = ev.getRules().indexWhere((r) => r.name == defaultName);
      await ev.removeRule(idx);

      final beforeHidden = ev.getHiddenDefaultRules().map((r) => r.name).toList();
      app.failOnNextWrite = true;
      await expectLater(
        ev.unhideRule(defaultName),
        throwsA(isA<Exception>()),
      );
      expect(ev.getHiddenDefaultRules().map((r) => r.name).toList(), equals(beforeHidden));
      expect(ev.getRules().any((r) => r.name == defaultName), isFalse);
    });
  });

  group('rule ordering', () {
    late InMemoryAppService app;
    late RuleEvaluator ev;

    setUp(() async {
      app = InMemoryAppService();
      ev = await _makeEvaluator(app);
    });

    test('new rule → appears at index 0 of combined list', () async {
      await ev.addRuleScript(_validScript);
      expect(ev.getRules().first.name, equals('myTest'));
    });

    test('reorderRules(0, 2) → rule moves from position 0 to 2', () async {
      await ev.addRuleScript(_validScript);
      final first = ev.getRules()[0].name;
      await ev.reorderRules(0, 2);
      expect(ev.getRules()[2].name, equals(first));
    });

    test('reorderRules can move a default rule above a user rule', () async {
      await ev.addRuleScript(_validScript);
      // After add, myTest is at 0; defaults follow. Move a default to 0.
      final names = ev.getRules().map((r) => r.name).toList();
      final firstDefaultIdx = names.indexWhere(
        (n) => defaultRules.any((d) => d.name == n),
      );
      final defaultName = names[firstDefaultIdx];
      await ev.reorderRules(firstDefaultIdx, 0);
      expect(ev.getRules().first.name, equals(defaultName));
    });

    test('order persists across init()', () async {
      await ev.addRuleScript(_validScript);
      await ev.reorderRules(0, 1);
      final expectedOrder = ev.getRules().map((r) => r.name).toList();

      final ev2 = await _makeEvaluator(app);
      final restoredOrder = ev2.getRules().map((r) => r.name).toList();
      expect(restoredOrder, equals(expectedOrder));
    });

    test('init() appends default rules missing from saved order (new app version defaults)', () async {
      // Ensure a non-empty saved order exists, then remove one default to simulate
      // a returning user whose saved order predates a newly-added default rule.
      await ev.addRuleScript(_validScript);
      final savedOrder = List<String>.from(await app.getRuleOrder());
      final missingDefault = defaultRules.last.name;
      savedOrder.remove(missingDefault);
      await app.setRuleOrder(savedOrder);

      final ev2 = await _makeEvaluator(app);
      expect(ev2.getRules().any((r) => r.name == missingDefault), isTrue);
    });
  });
}
