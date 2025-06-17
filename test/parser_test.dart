import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/util/color.dart';

import 'test_util.dart';

void main() {
  setupLogger(Level.FINE);

  RollDomain mockRollDomain = MockRollDomain();
  DieDomain mockDieDomain = MockDieDomain();
  GenericDie mockGenericDie = MockGenericDie();

  setUpAll(() {
    registerFallbackValue(MockColor());
    registerFallbackValue(mockGenericDie);
  });

  setUp(() {
    reset(mockRollDomain);
    reset(mockDieDomain);
    reset(mockGenericDie);
  });

  test('testHello', () async {
    expect(1, 1);
  });

  group("parser", () {
    test('parsed20PercentileRuleNoRun', () async {
      var rolls = [
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 3),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 19),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 13),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 2),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 5),
      ];

      RuleParser parser = RuleParser(mockDieDomain, mockRollDomain);

      ParseResult result = parser.runRule(d20percentiles, rolls, modifier: 3);
      expect(result.ruleReturn, false);
      verifyNever(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>())));
    });

    test('parsed20PercentileRule', () async {
      when(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>()))).thenAnswer((_) async {});
      var rolls = [
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 10),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 10),
      ];

      RuleParser parser = RuleParser(mockDieDomain, mockRollDomain);
      ParseResult result = parser.runRule(d20percentiles, rolls, modifier: 3);
      expect(result.ruleReturn, true);
      expect(result.result, 56); // (11 + 3) * 2 * 2.5, dice value plus modifier, 2 dice, percentile scale
      verify(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>()))).called(rolls.length);
    });

    test('parseStandardRoll', () async {
      when(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>()))).thenAnswer((_) async {});
      var rolls = [
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d4), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d8), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d10), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d00), index: 1),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d12), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 0),
      ];

      RuleParser parser = RuleParser(mockDieDomain, mockRollDomain);
      ParseResult result = parser.runRule(standardRoll, rolls);

      expect(result.ruleName, "standardRoll");
      expect(result.ruleReturn, true);
      expect(result.allRolled.length, rolls.length);
      expect(result.rolledEvaluated.length, rolls.length);
      expect(result.result, 16); // 1's on everything, except d00 which is 10
      verify(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>()))).called(rolls.length);
    });

    test('parseMaxRoll', () async {
      when(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>()))).thenAnswer((_) async {});
      var rolls = [
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d00), index: 1),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d4), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d8), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d10), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d12), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 0),
      ];

      RuleParser parser = RuleParser(mockDieDomain, mockRollDomain);
      ParseResult result = parser.runRule(maxRoll, rolls);

      expect(result.ruleName, "maxRoll");
      expect(result.ruleReturn, true);
      expect(result.allRolled.length, rolls.length);
      expect(result.rolledEvaluated.length, 1);
      expect(result.result, 10);
      verify(() => mockDieDomain.blink(colorMap["green"]!, any(that: isA<GenericDie>()))).called(1);
    });

    test('parseMinRoll', () async {
      when(() => mockDieDomain.blink(any(that: isA<Color>()), any(that: isA<GenericDie>()))).thenAnswer((_) async {});
      var rolls = [
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d4), index: 0),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d00), index: 9),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6), index: 5),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d8), index: 7),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d10), index: 9),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d12), index: 11),
        StaticVirtualDie(dType: GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20), index: 19),
      ];

      RuleParser parser = RuleParser(mockDieDomain, mockRollDomain);
      ParseResult result = parser.runRule(minRoll, rolls);

      expect(result.ruleName, "minRoll");
      expect(result.ruleReturn, true);
      expect(result.allRolled.length, rolls.length);
      expect(result.rolledEvaluated.length, 1);
      expect(result.result, 1);
      verify(() => mockDieDomain.blink(colorMap["red"]!, any(that: isA<GenericDie>()))).called(1);
    });
  });
}
