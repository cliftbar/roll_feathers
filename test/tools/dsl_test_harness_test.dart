import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/util/color.dart';

const String ruleHighLow = '''
define highLow for roll *d*

  make selection @ALL_MAX
    with match [\$MAX:\$MAX]

  make selection @ALL_MIN
    with match [\$MIN:\$MIN]

  use selection @ALL_MAX
    aggregate over selection count
    on result [1:*] action blink green

  use selection @ALL_MIN
    aggregate over selection count
    on result [1:*] action blink red
''';

void main() {
  test('DslTestRunner highlights highs and lows', () async {
    final runner = await DslTestRunner.create();
    final res = await runner.run(
      rule: ruleHighLow,
      dice: [
        DieInput('d6', 6, id: 'A'),
        DieInput('d6', 6, id: 'B'),
        DieInput('d6', 1, id: 'C'),
      ],
    );

    // Expect two greens (max) and one red (min)
    final greenVal = colorMap['green']!.value;
    final redVal = colorMap['red']!.value;
    final greens = res.actions.where((a) => a.colorValue == greenVal).toList();
    final reds = res.actions.where((a) => a.colorValue == redVal).toList();

    expect(greens.length, 2);
    expect(reds.length, 1);
  });
}
