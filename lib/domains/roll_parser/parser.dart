import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser_functions.dart';
import 'package:roll_feathers/domains/roll_parser/parser_transforms.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:tuple/tuple.dart';

const String modifierKey = "\$MODIFIER";
const String thresholdKey = "\$THRESHOLD";
const String allDiceKey = "\$ALL_DICE";
const String resultDiceKey = "\$RESULT_DICE";
const String rolledCountKey = "\$ROLLED_COUNT";

var _bool = ["true".toParser().map((b) => true), "false".toParser().map((b) => false)].toChoiceParser();

var _functions =
    [
      "sum".toParser().map((f) => sum),
      "min".toParser().map((f) => min),
      "max".toParser().map((f) => max),
      "avg".toParser().map((f) => avg),
    ].toChoiceParser();

var _transforms =
    [
      pp.seq3("top".toParser().map((f) => top), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
      pp.seq3(
        "bottom".toParser().map((f) => bottom),
        pp.whitespace().star(),
        number.repeatSeparated(" ".toParser(), 1, 1),
      ),
      pp.seq3(
        "equals".toParser().map((f) => equalsValue),
        pp.whitespace().star(),
        number.repeatSeparated(" ".toParser(), 1, 1),
      ),
      pp.seq3(
        "match".toParser().map((f) => match),
        pp.whitespace().star(),
        number.repeatSeparated(" ".toParser(), 1, 1),
      ),
      pp.seq3(
        "offset".toParser().map((f) => offset),
        pp.whitespace().star(),
        number.repeatSeparated(" ".toParser(), 1, 1),
      ),
      pp.seq3("mul".toParser().map((f) => mul), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
      pp.seq3("div".toParser().map((f) => div), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
      pp.seq3("over".toParser().map((f) => over), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
    ].toChoiceParser();

final integer = pp.digit().plus().flatten().map(num.parse);
final number = pp.digit()
    .plus()
    .seq(pp.char('.').seq(pp.digit().plus()).optional())
    .flatten()
    .trim()
    .map(num.parse);

var alphanumeric = pp.pattern('a-zA-Z0-9_').starString("defineName");
var wholeWord = pp.pattern('a-zA-Z0-9_').plus().flatten();
var variable = pp.seq2("\$".toParser(), pp.pattern('a-zA-Z0-9_').star()).flatten();
var _die = (numberOrStar & 'd'.toParser() & numberOrStar).flatten();

var transformDef = pp.seq4(
  pp.string("with").times(1).flatten(),
  pp.whitespace().star(),
  _transforms,
  pp.whitespace().star(),
);

const int intMaxValue = 9000000000000000;
const int intMinValue = -9000000000000000;
var numberOrStar = [number, "*".toParser()].toChoiceParser();
var openCloseIntervalStart = ["[".toParser(), "(".toParser()].toChoiceParser();
var openCloseIntervalEnd = ["]".toParser(), ")".toParser()].toChoiceParser();
var numStarVar = [number, "*".toParser(), variable].toChoiceParser();
var resultRange = pp.seq5(
  openCloseIntervalStart,
  [number, "*".toParser().map((e) => intMinValue)].toChoiceParser(),
  ":".toParser(),
  [number, "*".toParser().map((e) => intMaxValue)].toChoiceParser(),
  openCloseIntervalEnd,
);
var resultTarget =
    [
      (
        ResultTarget.rule.key.toParser(),
        pp.whitespace().star(),
        resultRules.keys.map((a) => a.toParser()).toChoiceParser(),
        pp.whitespace().star(),
        [variable, wholeWord].toChoiceParser().starSeparated(" ".toParser()),
      ).toSequenceParser(),
      (
        ResultTarget.action.key.toParser(),
        pp.whitespace().star(),
        resultActions.keys.map((a) => a.toParser()).toChoiceParser(),
        pp.whitespace().star(),
        [variable, wholeWord].toChoiceParser().starSeparated(" ".toParser()),
      ).toSequenceParser(),
      // ResultTarget.webhook.key.toParser()
    ].toChoiceParser();
var resultDef = pp.seq5("on".toParser(), pp.whitespace().star(), resultRange, pp.whitespace().star(), resultTarget);

enum ResultTarget {
  rule("rule"),
  webhook("webhook"),
  action("action");

  final String key;

  const ResultTarget(this.key);

  static ResultTarget? byKey(String key) {
    return ResultTarget.values.firstWhereOrNull((t) => t.key == key);
  }
}

class RollResultRange {
  late final bool startInclusive;
  late final int start;
  late final int end;
  late final bool endInclusive;

  RollResultRange(String startInclusive, this.start, this.end, String endInclusive) {
    this.startInclusive = startInclusive == "[";
    this.endInclusive = endInclusive == "]";
  }

  int getStart() {
    return startInclusive ? start : start + 1;
  }

  int getEnd() {
    return endInclusive ? end : end - 1;
  }

  bool valueIn(int value) {
    return getStart() <= value && value <= getEnd();
  }
}

class DieRollContainer {
  String dName;
  int value;

  DieRollContainer(this.dName, this.value);
}

class ParseResult {
  final int result;
  final Map<String, int> allRolled;
  final Map<String, int> rolledEvaluated;
  final String ruleName;
  final bool ruleReturn;
  final int? modifier;

  ParseResult({required this.result, required this.allRolled, required this.rolledEvaluated, required this.ruleName, required this.ruleReturn, this.modifier});
}

class RuleParser {
  final Logger _log = Logger("RuleParser");
  final DieDomain _dieDomain;
  final RollDomain _rollDomain;

  RuleParser(this._dieDomain, this._rollDomain);

  ParseResult runRule(String rule, List<GenericDie> rolls, {int threshold = 0, int modifier = 0}) {
    var replacedRule = rule.replaceAll(thresholdKey, threshold.toString());
    replacedRule = replacedRule.replaceAll(modifierKey, modifier.toString());
    replacedRule = replacedRule.replaceAll(rolledCountKey, rolls.length.toString());

    pp.Result<Map<Symbol, dynamic>> result = _parseRule(replacedRule);

    return _evaluateRule(rolls, result, threshold);
  }

  ParseResult _evaluateRule(List<GenericDie> rolls, pp.Result<Map<Symbol, dynamic>> result, int threshold) {
    // Check if the roll should evaluate
    var rollNames = rolls.map((d) => d.dType.name).toList();
    List<String> expandedResults =
        (result.value[#roll] as List<String>).expand((v) {
          if (v[0] == "*") {
            return [v];
          } else {
            int times = int.parse(v[0]);
            String dName = v.substring(1);
            return List.generate(times, (i) => dName.trim());
          }
        }).toList();
    bool passed = _checkRollConditions(expandedResults, rollNames);
    _log.fine("Should Evaluate: $rollNames, $passed");

    // Transform
    var rollMap = Map.fromEntries(rolls.map((r) => MapEntry(r, r.getFaceValueOrElse())));
    for (Tuple2<RollTransform, List<num>> transform in result.value[#transforms]) {
      var args = transform.item2.map((e) => threshold == e ? threshold : e).toList();
      rollMap = transform.item1(rollMap, args);
    }
    _log.fine("transformed: ${rollMap.values.toList()}");

    // apply roll aggregate
    int rollResult = (result.value[#aggregate] as RollAggregate)(rollMap.values.toList());

    _log.fine("Roll Result: $rollResult");

    // determine the rolls to make a result
    Map<String, int> evaluatedRolls = Map.fromEntries(rollMap.entries.map((e) => MapEntry(e.key.dieId, e.value)));
    Map<String, int> allRolls = Map.fromEntries(rolls.map((e) => MapEntry(e.dieId, e.getFaceValueOrElse())));
    if (!passed) {
      return ParseResult(result: rollResult, allRolled: allRolls, rolledEvaluated: evaluatedRolls, ruleName: result.value[#name], ruleReturn: passed);
    }
    // run actions if we should evaluate
    bool ruleReturn = true;
    for (Tuple4<RollResultRange, String, String, List<String>> res in result.value[#targets]) {
      if (!res.item1.valueIn(rollResult)) {
        continue;
      }
      var action = ResultTarget.byKey(res.item2)!;
      switch (action) {
        case ResultTarget.rule:
          ruleReturn = resultRules[res.item3]!(args: res.item4);
        case ResultTarget.action:
          List<GenericDie>? actionAllDice;
          if (res.item4.remove(allDiceKey)) {
            actionAllDice = rolls;
          }

          List<GenericDie>? actionResultDice;
          if (res.item4.remove(resultDiceKey)) {
            actionResultDice = rollMap.keys.toList();
          }
          resultActions[res.item3]!(
            dd: _dieDomain,
            rd: _rollDomain,
            allDice: actionAllDice,
            resultDice: actionResultDice,
            args: res.item4,
          );
        case ResultTarget.webhook:
      }
    }

    _log.fine("result: $ruleReturn");


    return ParseResult(result: rollResult, allRolled: allRolls, rolledEvaluated: evaluatedRolls, ruleName: result.value[#name], ruleReturn: ruleReturn);
  }

  pp.Result<Map<Symbol, dynamic>> _parseRule(String replacedRule) {
    var parser = pp
        .seq5(
          pp.seq3(pp.string("define ").times(1).flatten(), alphanumeric, pp.whitespace().star()),
          pp.seq4(
            pp.string("for roll ").times(1).flatten(),
            _die.plusSeparated(",".toParser()),
            " exactly".toParser().times(1).optional().map((e) => true),
            pp.whitespace().star(),
          ),
          pp
              .seq4(
                pp.string("transform").times(1).flatten(),
                pp.whitespace().star(),
                transformDef.starSeparated(pp.whitespace().star()),
                pp.whitespace().star(),
              )
              .optional(),
          pp.seq4(pp.string("aggregate").times(1).flatten(), " ".toParser().star(), _functions, pp.whitespace().star()),
          pp
              .seq4(
                pp.string("with result").times(1).flatten(),
                pp.whitespace().star(),
                resultDef.starSeparated(pp.whitespace().star()),
                pp.whitespace().star(),
              )
              .optional(),
        )
        .map5(
          (name, roll, transforms, aggregate, targets) => <Symbol, dynamic>{
            #name: name.$2,
            #roll: roll.$2.elements,
            #exactly: roll.$3,
            #transforms: transforms?.$3.elements.map((e) => Tuple2(e.$3.$1, e.$3.$3.elements)).toList(),
            #aggregate: aggregate.$3,
            #targets:
            targets?.$3.elements
                    .map((r) => Tuple4(RollResultRange(r.$3.$1, r.$3.$2.round(), r.$3.$4.round(), r.$3.$5), r.$5.$1, r.$5.$3, r.$5.$5.elements))
                    .toList(),
          },
        );
    var result = parser.parse(replacedRule);
    _log.fine(result.value);
    return result;
  }

  bool _checkRollConditions(List<String> expandedResults, List<String> rolls) {
    for (String expected in expandedResults) {
      if (expected == '*d*') {
        rolls.clear();
      } else if (expected[0] == "*") {
        rolls.removeWhere((r) => r == expected.substring(1));
      } else if (expected[1] == "*") {
        if (rolls.isEmpty) {
          rolls.clear();
          return false;
        } else {
          rolls.removeAt(0);
        }
      } else {
        int toRemove = rolls.indexWhere((r) => r == expected);
        if (toRemove != -1) {
          rolls.removeAt(toRemove);
        } else {
          return false;
        }
      }
    }

    return rolls.isEmpty;
  }
}
