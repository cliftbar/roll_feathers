import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/util/color.dart';

void main() {
  // Enable verbose logging so we can see the v1.1 evaluation flow in test output.
  setUpAll(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((rec) {
      // Print with level and logger name for easier debugging
      // ignore: avoid_print
      print('[${rec.level.name}] ${rec.loggerName}: ${rec.message}');
    });
  });
  group('d20percentiles sequence action', () {
    test('parses all color args and blinks in order with a leading loop count', () async {
      final runner = await DslTestRunner.create();

      // Two d20s showing 20 each -> after mul 2.5, sum = 100 -> triggers the [99:*) bucket
      final result = await runner.run(
        rule: d20percentiles,
        dice: [
          DieInput('d20', 20, id: 'D0'),
          DieInput('d20', 20, id: 'D1'),
        ],
      );

      // Updated sequence: sequence 1 red orange green blue violet
      // For each die: 5 colors x 1 loop = 5 blinks. With two dice -> 10 total blinks.
      // Debug: print parse result aggregate and actions length
      // ignore: avoid_print
      print('Aggregate=${result.parse.result} name=${result.parse.ruleName} actions=${result.actions.length}');
      expect(result.actions.length, 10);

      final expectedNames = <String>['red', 'orange', 'green', 'blue', 'violet'];
      final expectedOnce = expectedNames.map((n) => colorMap[n]!.value).toList(growable: false);

      // Actions are recorded die-by-die in sequence() implementation: all for D0, then all for D1.
      final d0 = result.actions.where((a) => a.dieId == 'D0').toList(growable: false);
      final d1 = result.actions.where((a) => a.dieId == 'D1').toList(growable: false);

      expect(d0.length, 5);
      expect(d1.length, 5);

      // Validate color order for each die (single loop of 5 colors)
      expect(d0.map((a) => a.colorValue).toList(growable: false), expectedOnce);
      expect(d1.map((a) => a.colorValue).toList(growable: false), expectedOnce);

      // Sanity: parser reported the correct rule name
      expect(result.parse.ruleName, 'd20percentiles');
    });
  });

  group('percentiles (1d10,1d00) sequence action', () {
    test('parses all color args and blinks in order with a leading loop count', () async {
      final runner = await DslTestRunner.create();

      // One d10 and one d00; choose values that sum >= 99 to trigger the [99:*) bucket.
      // Using 10 + 90 = 100 as a safe trigger.
      final result = await runner.run(
        rule: percentiles,
        dice: [
          DieInput('d10', 10, id: 'P0'),
          DieInput('d00', 90, id: 'P1'),
        ],
      );

      // Updated sequence: sequence 1 red orange green blue violet
      // For each die: 5 colors x 1 loop = 5 blinks. With two dice -> 10 total blinks.
      // ignore: avoid_print
      print('Aggregate=${result.parse.result} name=${result.parse.ruleName} actions=${result.actions.length}');
      expect(result.actions.length, 10);

      final expectedNames = <String>['red', 'orange', 'green', 'blue', 'violet'];
      final expectedOnce = expectedNames.map((n) => colorMap[n]!.value).toList(growable: false);

      final p0 = result.actions.where((a) => a.dieId == 'P0').toList(growable: false);
      final p1 = result.actions.where((a) => a.dieId == 'P1').toList(growable: false);

      expect(p0.length, 5);
      expect(p1.length, 5);

      expect(p0.map((a) => a.colorValue).toList(growable: false), expectedOnce);
      expect(p1.map((a) => a.colorValue).toList(growable: false), expectedOnce);

      expect(result.parse.ruleName, 'percentiles');
    });
  });
}
