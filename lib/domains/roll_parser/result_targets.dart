import 'package:collection/collection.dart' as cc;
import 'package:flutter/material.dart';
import 'package:petitparser/parser.dart' as pp;

import '../../dice_sdks/dice_sdks.dart';
import '../../domains/die_domain.dart';
import '../../util/color.dart';
import '../roll_domain.dart';
import 'parser_definitions.dart';

const int intMaxValue = 9000000000000000;
const int intMinValue = -9000000000000000;

typedef ResultTarget =
    Future<void> Function({
      required DieDomain dd,
      required RollDomain rd,
      List<GenericDie>? allDice,
      List<GenericDie>? resultDice,
      List<String> args,
    });

final pp.Parser<bool> startIntervalClosedParser =
    ["[".toParser().map((_) => true), "(".toParser().map((_) => false)].toChoiceParser();
final pp.Parser<bool> endIntervalClosedParser =
    ["]".toParser().map((_) => true), ")".toParser().map((_) => false)].toChoiceParser();

final pp.Parser<RollResultRange> resultRangeParser = pp
    .seq5<bool, num, String, num, bool>(
      startIntervalClosedParser,
      [numberParser, "*".toParser().map((e) => intMinValue)].toChoiceParser(),
      ":".toParser(),
      [numberParser, "*".toParser().map((e) => intMaxValue)].toChoiceParser(),
      endIntervalClosedParser,
    )
    .map5(
      ((bool startInclusive, num minVal, _, num maxVal, bool endInclusive) =>
          RollResultRange(startInclusive, minVal.round(), maxVal.round(), endInclusive)),
    );

final pp.Parser<ResultTargetFunction> resultTarget = [
  (
    ResultTargetType.rule.key.toParser().map((rt) => ResultTargetType.byKey(rt)),
    pp.whitespace().star(),
    resultRules.keys.map((a) => a.toParser()).toChoiceParser(),
    pp.whitespace().star(),
    [variableParser, wholeWordParser].toChoiceParser().starSeparated(" ".toParser()),
  ).toSequenceParser(),
  (
    ResultTargetType.action.key.toParser().map((rt) => ResultTargetType.byKey(rt)),
    pp.whitespace().star(),
    resultAction.keys.map((a) => a.toParser()).toChoiceParser(),
    pp.whitespace().star(),
    [variableParser, wholeWordParser].toChoiceParser().starSeparated(" ".toParser()),
  ).toSequenceParser(),
  // ResultTarget.webhook.key.toParser()
].toChoiceParser().map5(
  (ResultTargetType? targetType, _, String action, _, pp.SeparatedList<String, String> args) =>
      ResultTargetFunction(rtType: targetType!, action: action, args: args.elements),
);

final pp.Parser<ScriptResultTarget> resultDef = pp
    .seq5("on".toParser(), pp.whitespace().star(), resultRangeParser, pp.whitespace().star(), resultTarget)
    .map((entry) => ScriptResultTarget(entry.$3, entry.$5));

enum ResultTargetType {
  rule("rule"),
  webhook("webhook"),
  action("action");

  final String key;

  const ResultTargetType(this.key);

  static ResultTargetType? byKey(String key) {
    return ResultTargetType.values.firstWhereOrNull((t) => t.key == key);
  }
}

class ResultTargetFunction {
  ResultTargetType rtType;
  String action;
  List<String> args;

  ResultTargetFunction({required this.rtType, required this.action, required this.args});
}

class ScriptResultTarget {
  RollResultRange resultRange;
  ResultTargetFunction targetFunction;

  ScriptResultTarget(this.resultRange, this.targetFunction);
}

class RollResultRange {
  late final bool startInclusive;
  late final int start;
  late final int end;
  late final bool endInclusive;

  RollResultRange(this.startInclusive, this.start, this.end, this.endInclusive);

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

Future<void> blink({
  required DieDomain dd,
  required RollDomain rd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  List<String> args = const [],
}) async {
  for (GenericDie die in (resultDice ?? allDice ?? [])) {
    Color blinkColor = colorMap[args.firstOrNull] ?? die.blinkColor ?? Colors.white;
    dd.blink(blinkColor, die);
  }
}

Future<void> sequence({
  required DieDomain dd,
  required RollDomain rd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  List<String> args = const [],
}) async {
  int loops = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
  var defaultColors = ["red", "green", "blue"];
  for (GenericDie die in (resultDice ?? allDice ?? [])) {
    List<String> colorStrings = args.length < 2 ? defaultColors : args.sublist(1);
    List<String> colorLoops = [];
    for (int i = 0; i < loops; i++) {
      colorLoops.addAll(colorStrings);
    }
    for (var cs in colorLoops) {
      Color c = colorMap[cs] ?? Colors.white;
      // set instead of blink
      await dd.blink(c, die);
    }
  }
}

Map<String, ResultTarget> resultAction = {"blink": blink, "sequence": sequence};

typedef ResultRule = bool Function({List<String> args});

bool ret({List<String> args = const ["false"]}) {
  return bool.tryParse(args[0], caseSensitive: false) ?? false;
}

Map<String, ResultRule> resultRules = {"return": ret};
