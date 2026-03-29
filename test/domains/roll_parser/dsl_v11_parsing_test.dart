import 'dart:io';

import 'package:petitparser/petitparser.dart' as pp;
import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/domains/roll_parser/parser.dart';

void main() {
  group('DSL v1.1 parsing', () {
    final fixturesDir = Directory('test/fixtures');
    final parser = RuleParser.v11ScriptParser;

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
}
