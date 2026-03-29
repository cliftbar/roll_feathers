import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/util/color.dart';

// New/updated rule texts used in tests
const String ruleDoublesExactPairs = '''
define doubles for roll *d*

  make selection @DUPE2
    with dupes [2:2]

  use selection @DUPE2
    aggregate over selection count
    on result [1:*] action blink blue
''';

const String ruleTriplesExactly = '''
define nDupes for roll *d*

  make selection @NDUPE
    with dupes [3:3]

  use selection @NDUPE
    aggregate over selection count
    on result [1:*] action blink blue
''';

const String rulePairsExactly = '''
define nDupes for roll *d*

  make selection @NDUPE
    with dupes [2:2]

  use selection @NDUPE
    aggregate over selection count
    on result [1:*] action blink blue
''';

const String ruleHighLowAllTiesExclusive = '''
define highLowAllTiesExclusive for roll *d*

  make selection @ALL_MAX
    with match [\$MAX:\$MAX]

  make selection @ALL_MIN
    with match [\$MIN:\$MIN]

  make selection @DUPE_ANY
    with dupes [2:*]

  use selection @DUPE_ANY
    aggregate over selection count
    on result [\$ROLLED:\$ROLLED] action blink purple

  use selection @ALL_MAX
    aggregate over selection count
    on result [1:\$ROLLED) action blink green

  use selection @ALL_MIN
    aggregate over selection count
    on result [1:\$ROLLED) action blink red
''';

const String ruleHighLowTiesSingle = '''
define highLowTiesSingle for roll *d*

  make selection @HIGH
    with top 1

  make selection @LOW
    with bottom 1

  use selection @HIGH
    aggregate over selection max
    on result [\$MIN:\$MIN] action blink purple
    on result (\$MIN:*)   action blink green

  use selection @LOW
    aggregate over selection min
    on result [*:\$MAX) action blink red
''';

const String ruleHighLowSinglePreferMax = '''
define highLowSinglePreferMax for roll *d*

  make selection @HIGH
    with top 1

  make selection @LOW
    with bottom 1

  use selection @HIGH
    aggregate over selection max
    on result [\$MIN:\$MIN] action blink green
    on result (\$MIN:*)   action blink green

  use selection @LOW
    aggregate over selection min
    on result [*:\$MAX) action blink red
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('doubles (exact pairs)', () {
    test('selects only the two dice in a single pair', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: ruleDoublesExactPairs,
        dice: [
          DieInput('d6', 3, id: 'A'),
          DieInput('d6', 3, id: 'B'),
          DieInput('d6', 4, id: 'C'),
        ],
      );

      final blues = res.actions.where((a) => a.colorValue == colorMap['blue']!.value).toList();
      expect(blues.map((a) => a.dieId).toSet(), {'A', 'B'});
    });

    test('triple-of-a-kind does not count as an exact pair', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: ruleDoublesExactPairs,
        dice: [
          DieInput('d6', 2, id: 'A'),
          DieInput('d6', 2, id: 'B'),
          DieInput('d6', 2, id: 'C'),
        ],
      );
      final blues = res.actions.where((a) => a.colorValue == colorMap['blue']!.value).toList();
      expect(blues.length, 0);
    });
  });

  group('nDupes (exact N)', () {
    test('N=3 selects all dice in triple', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: ruleTriplesExactly,
        dice: [
          DieInput('d6', 2, id: 'A'),
          DieInput('d6', 2, id: 'B'),
          DieInput('d6', 2, id: 'C'),
          DieInput('d6', 5, id: 'D'),
        ],
      );
      final blues = res.actions.where((a) => a.colorValue == colorMap['blue']!.value).toList();
      expect(blues.map((a) => a.dieId).toSet(), {'A', 'B', 'C'});
    });

    test('N=2 does not select triples', () async {
      final runner = await DslTestRunner.create();
      final res = await runner.run(
        rule: rulePairsExactly,
        dice: [
          DieInput('d6', 4, id: 'A'),
          DieInput('d6', 4, id: 'B'),
          DieInput('d6', 4, id: 'C'),
        ],
      );
      final blues = res.actions.where((a) => a.colorValue == colorMap['blue']!.value).toList();
      expect(blues.length, 0);
    });
  });

  group('high/low variants', () {
    test('highLowAllTiesExclusive — tie: purple only; mixed: green/red only', () async {
      final runner = await DslTestRunner.create();

      // Tie: 3,3
      final tie = await runner.run(
        rule: ruleHighLowAllTiesExclusive,
        dice: [DieInput('d6', 3, id: 'A'), DieInput('d6', 3, id: 'B')],
      );
      final tiePurples = tie.actions.where((a) => a.colorValue == colorMap['purple']!.value).length;
      final tieGreens = tie.actions.where((a) => a.colorValue == colorMap['green']!.value).length;
      final tieReds = tie.actions.where((a) => a.colorValue == colorMap['red']!.value).length;
      expect(tiePurples, 2);
      expect(tieGreens, 0);
      expect(tieReds, 0);

      // Mixed: 6,1,6
      final mixed = await runner.run(
        rule: ruleHighLowAllTiesExclusive,
        dice: [
          DieInput('d6', 6, id: 'X'),
          DieInput('d6', 1, id: 'Y'),
          DieInput('d6', 6, id: 'Z'),
        ],
      );
      final mPurples = mixed.actions.where((a) => a.colorValue == colorMap['purple']!.value).length;
      final mGreens = mixed.actions.where((a) => a.colorValue == colorMap['green']!.value).length;
      final mReds = mixed.actions.where((a) => a.colorValue == colorMap['red']!.value).length;
      expect(mPurples, 0);
      expect(mGreens, 2);
      expect(mReds, 1);
    });

    test('highLowTiesSingle — tie: exactly one purple; mixed: one green and one red', () async {
      final runner = await DslTestRunner.create();
      final tie = await runner.run(
        rule: ruleHighLowTiesSingle,
        dice: [DieInput('d6', 4, id: 'A'), DieInput('d6', 4, id: 'B')],
      );
      final tiePurples = tie.actions.where((a) => a.colorValue == colorMap['purple']!.value).length;
      final tieGreens = tie.actions.where((a) => a.colorValue == colorMap['green']!.value).length;
      final tieReds = tie.actions.where((a) => a.colorValue == colorMap['red']!.value).length;
      expect(tiePurples, 1);
      expect(tieGreens, 0);
      expect(tieReds, 0);

      final mixed = await runner.run(
        rule: ruleHighLowTiesSingle,
        dice: [DieInput('d6', 6, id: 'H'), DieInput('d6', 1, id: 'L')],
      );
      final greens = mixed.actions.where((a) => a.colorValue == colorMap['green']!.value).length;
      final reds = mixed.actions.where((a) => a.colorValue == colorMap['red']!.value).length;
      expect(greens, 1);
      expect(reds, 1);
    });

    test('highLowSinglePreferMax — tie: only one green; mixed: one green and one red', () async {
      final runner = await DslTestRunner.create();
      final tie = await runner.run(
        rule: ruleHighLowSinglePreferMax,
        dice: [DieInput('d6', 2, id: 'A'), DieInput('d6', 2, id: 'B')],
      );
      final tieGreens = tie.actions.where((a) => a.colorValue == colorMap['green']!.value).length;
      final tieReds = tie.actions.where((a) => a.colorValue == colorMap['red']!.value).length;
      expect(tieGreens, 1);
      expect(tieReds, 0);

      final mixed = await runner.run(
        rule: ruleHighLowSinglePreferMax,
        dice: [DieInput('d6', 5, id: 'H'), DieInput('d6', 1, id: 'L')],
      );
      final greens = mixed.actions.where((a) => a.colorValue == colorMap['green']!.value).length;
      final reds = mixed.actions.where((a) => a.colorValue == colorMap['red']!.value).length;
      expect(greens, 1);
      expect(reds, 1);
    });
  });
}
