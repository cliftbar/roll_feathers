import 'package:flutter_test/flutter_test.dart';
import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

void main() {
  group('Webhook DSL parsing', () {
    // Parse the resultTarget parser directly for quick unit tests on the fragment.
    ResultTargetFunction parseTarget(String input) {
      final result = resultTarget.parse(input);
      if (!result.isSuccess) fail('Failed to parse: $input\n${(result as pp.Failure).message}');
      return result.value;
    }

    test('1.1 explicit POST parses method and URL', () {
      final t = parseTarget('webhook POST https://example.com/roll');
      expect(t.rtType, equals(ResultTargetType.webhook));
      expect(t.target, equals('https://example.com/roll'));
      expect(t.args, equals(['POST']));
    });

    test('1.2 explicit GET parses method and URL', () {
      final t = parseTarget('webhook GET https://example.com/roll');
      expect(t.rtType, equals(ResultTargetType.webhook));
      expect(t.target, equals('https://example.com/roll'));
      expect(t.args, equals(['GET']));
    });

    test('1.3 omitted method defaults to POST', () {
      final t = parseTarget('webhook https://example.com/roll');
      expect(t.rtType, equals(ResultTargetType.webhook));
      expect(t.target, equals('https://example.com/roll'));
      expect(t.args, equals(['POST']));
    });

    test('1.4 method keyword is case-insensitive: lowercase get', () {
      final t = parseTarget('webhook get https://example.com/hook');
      expect(t.args, equals(['GET']));
      expect(t.target, equals('https://example.com/hook'));
    });

    test('1.5 method keyword is case-insensitive: lowercase post', () {
      final t = parseTarget('webhook post https://example.com/hook');
      expect(t.args, equals(['POST']));
      expect(t.target, equals('https://example.com/hook'));
    });

    test('1.6 URL with path segments preserved', () {
      final t = parseTarget('webhook POST https://example.com/a/b/c');
      expect(t.target, equals('https://example.com/a/b/c'));
    });

    test('1.7 URL with query string preserved', () {
      final t = parseTarget('webhook POST https://example.com/hook?foo=bar&baz=qux');
      expect(t.target, equals('https://example.com/hook?foo=bar&baz=qux'));
    });

    test('1.8 unknown method prefix treated as part of URL', () {
      // "DELETE" is not GET or POST, so treated as start of URL.
      final t = parseTarget('webhook DELETE https://example.com');
      expect(t.args, equals(['POST']));
      expect(t.target, startsWith('DELETE'));
    });

    test('1.9 webhook POST in full v11 script parses successfully', () {
      const script = '''
define hook_test for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] webhook POST https://example.com/roll
''';
      final result = RuleEvaluator.v11ScriptParser.parse(script);
      if (!result.isSuccess) fail('Failed to parse script: ${(result as pp.Failure).message}');
      final block = result.value.useBlocks.first;
      expect(block.targets.length, equals(1));
      expect(block.targets.first.targetFunction.rtType, equals(ResultTargetType.webhook));
      expect(block.targets.first.targetFunction.args, equals(['POST']));
      expect(block.targets.first.targetFunction.target, equals('https://example.com/roll'));
    });

    test('1.10 webhook GET in full v11 script with specific range', () {
      const script = '''
define hook_get for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [5:15] webhook GET https://example.com/hook
''';
      final result = RuleEvaluator.v11ScriptParser.parse(script);
      if (!result.isSuccess) fail('Failed to parse script: ${(result as pp.Failure).message}');
      final target = result.value.useBlocks.first.targets.first;
      expect(target.targetFunction.rtType, equals(ResultTargetType.webhook));
      expect(target.targetFunction.args, equals(['GET']));
      expect(target.resultRange.startInclusive, isTrue);
      expect(target.resultRange.start, equals(5));
      expect(target.resultRange.end, equals(15));
      expect(target.resultRange.endInclusive, isTrue);
    });

    test('1.11 ResultTargetType.byKey resolves webhook', () {
      expect(ResultTargetType.byKey('webhook'), equals(ResultTargetType.webhook));
    });

    test('1.12 webhook coexists with action target in same block', () {
      const script = '''
define coexist for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink blue
    on result [*:*] webhook POST https://example.com/roll
''';
      final result = RuleEvaluator.v11ScriptParser.parse(script);
      if (!result.isSuccess) fail('Failed to parse script: ${(result as pp.Failure).message}');
      final targets = result.value.useBlocks.first.targets;
      expect(targets.length, equals(2));
      final types = targets.map((t) => t.targetFunction.rtType).toSet();
      expect(types, containsAll([ResultTargetType.action, ResultTargetType.webhook]));
    });
  });
}
