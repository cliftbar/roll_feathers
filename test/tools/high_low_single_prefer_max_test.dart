import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/util/color.dart';

// DSL rule: blink a single highest (green) and a single lowest (red);
// on tie, prefer the max (blink only the single max green; no red/purple)
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

  test('highLowSinglePreferMax — tie prefers max (only one green, no red)', () async {
    final runner = await DslTestRunner.create();
    final res = await runner.run(
      rule: ruleHighLowSinglePreferMax,
      dice: [
        DieInput('d6', 3, id: 'A'),
        DieInput('d6', 3, id: 'B'),
        DieInput('d6', 3, id: 'C'),
      ],
    );

    final greens = res.actions.where((a) => a.colorValue == colorMap['green']!.value).toList();
    final reds = res.actions.where((a) => a.colorValue == colorMap['red']!.value).toList();

    expect(greens.length, 1, reason: 'Exactly one top die should blink green on tie');
    expect(reds.length, 0, reason: 'No red on tie');
  });

  test('highLowSinglePreferMax — mixed values: one green (max) and one red (min)', () async {
    final runner = await DslTestRunner.create();
    final res = await runner.run(
      rule: ruleHighLowSinglePreferMax,
      dice: [
        DieInput('d6', 6, id: 'H'),
        DieInput('d6', 1, id: 'L'),
        DieInput('d6', 4, id: 'M'),
      ],
    );

    final greens = res.actions.where((a) => a.colorValue == colorMap['green']!.value).toList();
    final reds = res.actions.where((a) => a.colorValue == colorMap['red']!.value).toList();

    expect(greens.length, 1, reason: 'Exactly one highest die should blink green');
    expect(reds.length, 1, reason: 'Exactly one lowest die should blink red');
  });
}
