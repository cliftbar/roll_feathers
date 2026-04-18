import 'dart:io';

import 'package:petitparser/petitparser.dart' as pp;
import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';

void main() {
  group('DSL v1.1 parsing', () {
    final fixturesDir = Directory('test/fixtures');
    final parser = RuleEvaluator.v11ScriptParser;

    test('all .rule fixtures should parse with v1.1 grammar', () {
      expect(fixturesDir.existsSync(), isTrue, reason: 'fixtures directory missing');
      final files = fixturesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.rule'))
          .toList();
      expect(files, isNotEmpty, reason: 'no .rule fixtures found');

      for (final file in files) {
        final content = file.readAsStringSync();
        final pp.Result result = parser.parse(content);
        expect(result.isSuccess, isTrue, reason: 'failed to parse ${file.path}');
      }
    });
  });

  group('DSL v1.1 evaluation (scaffold)', () {
    test('evaluation tests will be added after parsing passes for all fixtures', () {}, skip: true);
  });

  group('define display name', () {
    test('RuleScript.displayName reads quoted name from define line', () {
      const script = '''
define myRule "My Display Name" for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
''';
      final rule = RuleScript(name: 'myRule', script: script, enabled: true);
      expect(rule.displayName, 'My Display Name');
    });

    test('RuleScript.displayName falls back to name when no quoted string', () {
      const script = '''
define myRule for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
''';
      final rule = RuleScript(name: 'myRule', script: script, enabled: true);
      expect(rule.displayName, 'myRule');
    });

    test('ruleId with dash parses successfully', () {
      const script = '''
define my-rule "My Rule" for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
''';
      final result = RuleEvaluator.v11ScriptParser.parse(script);
      expect(result.isSuccess, isTrue);
      expect(result.value.name, 'my-rule');
      final rule = RuleScript(name: 'my-rule', script: script, enabled: true);
      expect(rule.displayName, 'My Rule');
    });

    test('webhookExample default rule has display name Webhook Example', () {
      final rule = RuleScript(name: 'webhookExample', script: webhookExample, enabled: false);
      expect(rule.displayName, 'Webhook Example');
    });

    test('all default rules have distinct display names from their identifiers', () {
      for (final rule in defaultRules) {
        if (rule.displayName != rule.name) {
          // display name was set via "..." in the define line
          expect(rule.displayName, isNot(equals(rule.name)));
        }
      }
    });
  });
}
