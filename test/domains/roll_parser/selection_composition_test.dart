import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';

/// `dtype <name>` and multi-parent `from @A, @B` (last wins).
/// See docs/specs/dsl_selection_composition.md.
void main() {
  group('dtype filter', () {
    const onlyD00 = r'''
define onlyD00 "Only d00" for roll 1d10,1d00

  make selection @T
    from $ALL_DICE
    with dtype d00

  use selection @T
    aggregate over selection sum
    on result [0:*] action blink blue

  report sum over @T
''';

    test('keeps only dice of the named type', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: onlyD00,
        dice: [DieInput('d10', 7, id: 'ones'), DieInput('d00', 40, id: 'tens')],
      );

      expect(res.parse.rolledEvaluated.keys.toSet(), {'tens'});
      expect(res.parse.result, 40);
    });

    test('an unrecognised type name yields an empty selection, not an error', () async {
      final runner = await DslTestRunner.create();
      const unknown = r'''
define unknownType "Unknown" for roll 1d10,1d00

  make selection @T
    from $ALL_DICE
    with dtype d7

  use selection @T
    aggregate over selection sum
    on result [1:*] action blink blue

  report sum over @T
''';
      final res = await runner.run(
        rule: unknown,
        dice: [DieInput('d10', 7, id: 'ones'), DieInput('d00', 40, id: 'tens')],
      );

      expect(res.parse.matchedResult, isFalse);
      expect(res.actions, isEmpty);
    });
  });

  group('multi-parent from', () {
    /// @B overrides @A for the die they share; @A's other dice survive.
    const merge = r'''
define mergeRule "Merge" for roll 1d10,1d00

  make selection @A
    from $ALL_DICE

  make selection @B
    from $ALL_DICE
    with dtype d00
    with offset 100

  make selection @M
    from @A, @B

  use selection @M
    aggregate over selection sum
    on result [0:*] action blink blue

  report sum over @M
''';

    test('later parent wins on a shared die; others pass through', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: merge,
        dice: [DieInput('d10', 7, id: 'ones'), DieInput('d00', 40, id: 'tens')],
      );

      // tens overridden to 140 by @B, ones untouched from @A.
      expect(res.parse.rolledEvaluated, {'ones': 7, 'tens': 140});
      expect(res.parse.result, 147);
    });

    test('an empty later parent leaves the earlier one intact', () async {
      final runner = await DslTestRunner.create();
      const emptyOverride = r'''
define emptyOverride "Empty Override" for roll 1d10,1d00

  make selection @A
    from $ALL_DICE

  make selection @B
    from $ALL_DICE
    with dtype d7

  make selection @M
    from @A, @B

  use selection @M
    aggregate over selection sum
    on result [0:*] action blink blue

  report sum over @M
''';
      final res = await runner.run(
        rule: emptyOverride,
        dice: [DieInput('d10', 7, id: 'ones'), DieInput('d00', 40, id: 'tens')],
      );

      expect(res.parse.rolledEvaluated, {'ones': 7, 'tens': 40});
      expect(res.parse.result, 47);
    });

    test('single-parent from is unchanged', () async {
      final runner = await DslTestRunner.create();
      const single = r'''
define singleParent "Single" for roll 1d10,1d00

  make selection @A
    from $ALL_DICE
    with dtype d10

  make selection @B
    from @A

  use selection @B
    aggregate over selection sum
    on result [0:*] action blink blue

  report sum over @B
''';
      final res = await runner.run(
        rule: single,
        dice: [DieInput('d10', 7, id: 'ones'), DieInput('d00', 40, id: 'tens')],
      );

      expect(res.parse.rolledEvaluated.keys.toSet(), {'ones'});
      expect(res.parse.result, 7);
    });
  });

  group('percentiles rule — the worked example', () {
    // Every row of the table in docs/specs/dsl_selection_composition.md.
    // (d00 shows, d10 shows, expected total, expected per-die values)
    final cases = <List<Object>>[
      [0, 0, 100, {'tens': 100, 'ones': 0}],
      [0, 1, 1, {'tens': 0, 'ones': 1}],
      [0, 5, 5, {'tens': 0, 'ones': 5}],
      [10, 0, 10, {'tens': 10, 'ones': 0}],
      [40, 7, 47, {'tens': 40, 'ones': 7}],
      [70, 3, 73, {'tens': 70, 'ones': 3}],
      [90, 0, 90, {'tens': 90, 'ones': 0}],
      [90, 9, 99, {'tens': 90, 'ones': 9}],
    ];

    for (final c in cases) {
      final tens = c[0] as int;
      final ones = c[1] as int;
      final expected = c[2] as int;
      final dice = c[3] as Map<String, int>;

      test('d00=$tens d10=$ones -> $expected', () async {
        final runner = await DslTestRunner.create();
        final res = await runner.run(
          rule: percentiles,
          dice: [DieInput('d10', ones, id: 'ones'), DieInput('d00', tens, id: 'tens')],
        );

        expect(res.parse.result, expected);
        // Per-die fidelity is the whole point: 00+0 must read 100 and 0, not
        // two dice at 50 or two dice at 0 with a patched total.
        expect(res.parse.rolledEvaluated, dice);
      });
    }

    test('00+0 lands in the top band, not the bottom one', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: percentiles,
        dice: [DieInput('d10', 0, id: 'ones'), DieInput('d00', 0, id: 'tens')],
      );

      // The old rule summed to 0, hit `[0:10)` and blinked red. 100 must reach
      // the `[99:*)` sequence instead.
      expect(res.parse.result, 100);
      expect(res.actions.length, greaterThan(1), reason: 'sequence, not a single blink');
    });
  });

  group('sharp edges', () {
    test('dtype before dupes silently never fires — characterised, not endorsed', () async {
      final runner = await DslTestRunner.create();
      const wrongOrder = r'''
define wrongOrder "Wrong Order" for roll 1d10,1d00

  make selection @H
    from $ALL_DICE
    with match [0:0]
    with dtype d00
    with dupes [2:2]
    with offset 100

  use selection @H
    aggregate over selection sum
    on result [1:*] action blink blue

  report sum over @H
''';
      // Narrowing to one die first means dupes [2:2] can never match.
      final res = await runner.run(
        rule: wrongOrder,
        dice: [DieInput('d10', 0, id: 'ones'), DieInput('d00', 0, id: 'tens')],
      );

      expect(res.parse.matchedResult, isFalse,
          reason: 'documents the ordering trap in the spec');
    });
  });
}
