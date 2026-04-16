import 'package:flutter_test/flutter_test.dart';
import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

ResultTargetFunction _parseTarget(String input) {
  final result = resultTarget.parse(input);
  if (!result.isSuccess) fail('Failed to parse: $input\n${(result as pp.Failure).message}');
  return result.value;
}

void main() {
  group('Soundclip DSL parsing', () {
    test('4.1 soundclip <name> parses correctly', () {
      final t = _parseTarget('soundclip victory');
      expect(t.rtType, equals(ResultTargetType.soundclip));
      expect(t.action, equals('victory'));
      expect(t.args, isEmpty);
    });

    test('4.2 name with underscores', () {
      final t = _parseTarget('soundclip roll_hit');
      expect(t.action, equals('roll_hit'));
    });

    test('4.3 name with numbers', () {
      final t = _parseTarget('soundclip clip123');
      expect(t.action, equals('clip123'));
    });

    test('4.4 ResultTargetType.byKey resolves soundclip', () {
      expect(ResultTargetType.byKey('soundclip'), equals(ResultTargetType.soundclip));
    });

    test('4.5 soundclip in full v11 script', () {
      const script = '''
define sc_test for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] soundclip victory
''';
      final result = RuleParser.v11ScriptParser.parse(script);
      if (!result.isSuccess) fail('Parse failed: ${(result as pp.Failure).message}');
      final target = result.value.useBlocks.first.targets.first;
      expect(target.targetFunction.rtType, equals(ResultTargetType.soundclip));
      expect(target.targetFunction.action, equals('victory'));
    });

    test('4.6 soundclip coexists with action in same block', () {
      const script = '''
define coexist for roll *d*
  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink blue
    on result [*:*] soundclip victory
''';
      final result = RuleParser.v11ScriptParser.parse(script);
      if (!result.isSuccess) fail('Parse failed: ${(result as pp.Failure).message}');
      final targets = result.value.useBlocks.first.targets;
      expect(targets.length, equals(2));
      final types = targets.map((t) => t.targetFunction.rtType).toSet();
      expect(types, containsAll([ResultTargetType.action, ResultTargetType.soundclip]));
    });
  });
}
