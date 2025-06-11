import 'package:collection/collection.dart';

import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_parser/parser_functions.dart';
import 'package:roll_feathers/domains/roll_parser/parser_transforms.dart';
import 'package:tuple/tuple.dart';



const String modifierKey = "\$modifier";
const String thresholdKey = "\$threshold";
const String allDiceKey = "\$ALL_DICE";
const String resultDiceKey = "\$RESULT_DICE";
const String diceRolledKey = "\$DICE_ROLLED";

var _bool = [
  "true".toParser().map((b) => true),
  "false".toParser().map((b) => false),
].toChoiceParser();

var _functions = [
  "sum".toParser().map((f) => sum),
  "min".toParser().map((f) => min),
  "max".toParser().map((f) => max),
  "avg".toParser().map((f) => avg),
].toChoiceParser();

var _transforms = [
  pp.seq3("top".toParser().map((f) => top), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("bottom".toParser().map((f) => bottom), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("match".toParser().map((f) => match), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("offset".toParser().map((f) => offset), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("mul".toParser().map((f) => mul), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("div".toParser().map((f) => div), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("over".toParser().map((f) => over), pp.whitespace().star(), number.repeatSeparated(" ".toParser(), 1, 1)),
].toChoiceParser();

final number = pp.digit().plus().flatten().map(int.parse);

var alphanumeric = pp.pattern('a-zA-Z0-9_').starString("defineName");
var variable = pp.seq2("\$".toParser(), pp.pattern('a-zA-Z0-9_').star()).flatten();
var _die = (numberOrStar & 'd'.toParser() & numberOrStar).flatten();

var transformDef = pp.seq4(pp.string("with").times(1).flatten(), pp.whitespace().star(), _transforms, pp.whitespace().star());

const int intMaxValue = 9000000000000000;
const int intMinValue = -9000000000000000;
var numberOrStar = [number, "*".toParser()].toChoiceParser();
var openCloseIntervalStart = ["[".toParser(), "(".toParser()].toChoiceParser();
var openCloseIntervalEnd = ["]".toParser(), ")".toParser()].toChoiceParser();
var numStarVar = [number, "*".toParser(), variable].toChoiceParser();
var resultRange = pp.seq5(openCloseIntervalStart, [number, "*".toParser().map((e) => intMinValue)].toChoiceParser(), ":".toParser(), [number, "*".toParser().map((e) => intMaxValue)].toChoiceParser(), openCloseIntervalEnd);
var resultTarget = [
  (ResultTarget.ret.key.toParser(), pp.whitespace().star(), _bool).toSequenceParser(),
  // (ResultTarget.action.key.toParser(), pp.whitespace().star()),
  // ResultTarget.webhook.key.toParser()
].toChoiceParser();
var resultDef = pp.seq5("on".toParser(), pp.whitespace().star(), resultRange, pp.whitespace().star(), resultTarget);

enum ResultTarget {
  ret("return"),
  webhook("webhook"),
  action("action")
  ;
  final String key;

  const ResultTarget(this.key);

  static ResultTarget? byKey(String key) {
    return ResultTarget.values.firstWhereOrNull((t) => t.key == key);
  }

}

class DieRollContainer {
  String dName;
  int value;

  DieRollContainer(this.dName, this.value);
}

void parseRule(String rule, List<GenericDie> rolls, {int threshold = 0, int modifier = 0}) {
  var replacedRule = rule.replaceAll(thresholdKey, threshold.toString());
  replacedRule = replacedRule.replaceAll(modifierKey, modifier.toString());
  replacedRule = replacedRule.replaceAll(diceRolledKey, rolls.length.toString());

  var parser = pp.seq5(
    pp.seq3(pp.string("define ").times(1).flatten(), alphanumeric, pp.whitespace().star()),
    pp.seq4(pp.string("for roll ").times(1).flatten(), _die.plusSeparated(",".toParser()), " exactly".toParser().times(1).optional().map((e) => true), pp.whitespace().star()),
    pp.seq4(pp.string("transform").times(1).flatten(), pp.whitespace().star(), transformDef.starSeparated(pp.whitespace().star()), pp.whitespace().star()).optional(),
    pp.seq3(pp.string("apply ").times(1).flatten(), _functions, pp.whitespace().star()),
    pp.seq4(pp.string("with result").times(1).flatten(), pp.whitespace().star(), resultDef.starSeparated(pp.whitespace().star()), pp.whitespace().star()).optional(),
  ).map5((name, dieParse, transforms, apply, results) => <Symbol, dynamic>{
    #name: name.$2,
    #dice: dieParse.$2.elements,
    #exactly: dieParse.$3,
    #transforms: transforms?.$3.elements.map((e) => Tuple2(e.$3.$1, e.$3.$3.elements)).toList(),
    #aggregate: apply.$2,
    #results: results?.$3.elements.map((r) => Tuple3(RollResultRange(r.$3.$1, r.$3.$2, r.$3.$4, r.$3.$5), r.$5.$1, r.$5.$3)).toList(),

  });
  var result = parser.parse(replacedRule);
  print(result.value);


  // Check if the roll should evaluate
  var rollNames = rolls.map((d) => d.dType.name).toList();
  List<String> expandedResults = (result.value[#dice] as List<String>).expand((v) {
    if (v[0] == "*") {
      return [v];
    } else {
      int times = int.parse(v[0]);
      String dName = v.substring(1);
      return List.generate(times, (i) => dName);
    }
  }).toList();
  bool passed = checkRollConditions(expandedResults, rollNames);
  print("Should Evaluate: $rollNames, $passed");

  // Transform
  var rollMap = Map.fromEntries(rolls.map((r) => MapEntry(r, r.getFaceValueOrElse())));
  for (Tuple2<RollTransform, List<int>> transform in result.value[#transforms]) {
    var args = transform.item2.map((e) => threshold == e ? threshold : e).toList();
    rollMap = transform.item1(rollMap, args);
  }
  print("transformed: ${rollMap.values.toList()}");

  // apply roll aggregate
  int rollResult = (result.value[#aggregate] as RollAggregate)(rollMap.values.toList());
  print("Roll Result: $rollResult");

  bool ret = true;
  for (Tuple3<RollResultRange, String, bool> res in result.value[#results]) {
    var action = ResultTarget.byKey(res.item2)!;
    switch(action) {

      case ResultTarget.ret:
        if (res.item1.valueIn(rollResult)) {
          ret = res.item3;
        }
      case ResultTarget.webhook:
      case ResultTarget.action:
    }
  }

  print("result: $ret");

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

bool checkRollConditions(List<String> expandedResults, List<String> rolls) {
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

  return true;
}