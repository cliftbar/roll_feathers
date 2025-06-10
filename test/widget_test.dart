import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/parser.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

void main() {
  test('testHello', () async {
    expect(1, 1);
  });

  test('parseRule', () async {
    var result = RollResult(rollType: RollType.sum, rollResult: 10, rolls: {"1": 4, "2": 6});

    var rolls = [StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d10), index: 9), StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d00), index: 3)];
    parseRule(rulePercentileSuccess, 12, 3, rolls);
    parseRule(ruleAdvantage, 12, 3, rolls);
  });
}
