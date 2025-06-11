import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';

void main() {
  test('testHello', () async {
    expect(1, 1);
  });

  test('parseRule', () async {
    var result = RollResult(rollType: RollType.sum, rollResult: 10, rolls: {"1": 4, "2": 6});

    var rolls = [
      StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 3),
      StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 19),
      StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 13),
      StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 2),
      StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 5)
    ];
    // parseRule(isSuccessPercentile, 12, 3, rolls);
    parseRule(testRule, rolls, threshold: 41, modifier: 3);
  });
}
