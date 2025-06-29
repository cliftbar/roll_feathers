import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser_aggregates.dart';
import 'package:roll_feathers/domains/roll_parser/parser_definitions.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/domains/roll_parser/parser_transforms.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

import '../../services/app_service.dart';

const String modifierKey = "\$MODIFIER";
const String thresholdKey = "\$THRESHOLD";
const String allDiceKey = "\$ALL_DICE";
const String resultDiceKey = "\$RESULT_DICE";
const String rolledCountKey = "\$ROLLED_COUNT";

final pp.Parser<String> dieParser = (numberOrStarParser & 'd'.toParser() & numberOrStarParser).flatten();

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

  ParseResult({
    required this.result,
    required this.allRolled,
    required this.rolledEvaluated,
    required this.ruleName,
    required this.ruleReturn,
    this.modifier,
  });
}

class ParsedScript {
  String name;
  List<String> roll;
  bool exactly;
  List<ScriptTransform> transforms;
  RollAggregate aggregate;
  List<ScriptResultTarget> targets;
  // do this better
  String? script;

  ParsedScript({
    required this.name,
    required this.roll,
    required this.exactly,
    required this.transforms,
    required this.aggregate,
    required this.targets,
    this.script,
  });
}

class RuleParser {
  static final pp.Parser<ParsedScript> scriptParser = pp
      .seq5(
        pp.seq3(pp.string("define ").times(1).flatten(), alphanumericParser, pp.whitespace().star()),
        pp.seq4(
          pp.string("for roll ").times(1).flatten(),
          dieParser.plusSeparated(",".toParser()),
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
        pp.seq4(
          pp.string("aggregate").times(1).flatten(),
          " ".toParser().star(),
          aggregateParsers,
          pp.whitespace().star(),
        ),
        pp
            .seq4(
              pp.string("with result").times(1).flatten(),
              pp.whitespace().star(),
              resultDef.starSeparated(pp.whitespace().star()),
              pp.whitespace().star(),
            )
            .optional(),
      )
      .map5((name, roll, transforms, aggregate, targets) {
        return ParsedScript(
          name: name.$2,
          roll: roll.$2.elements,
          exactly: roll.$3,
          transforms: transforms?.$3.elements ?? [],
          aggregate: aggregate.$3,
          targets: targets?.$3.elements ?? [],
        );
      });

  final Logger _log = Logger("RuleParser");
  final DieDomain _dieDomain;
  final RollDomain _rollDomain;

  late final List<RuleScript> _userRules;

  List<RuleScript> getRules({bool enabledOnly = false}) {
    // TODO: not a great check here
    List<RuleScript> ret = [];
    ret.addAll(_userRules);
    for (var r in defaultRules) {
      if (!ret.map((e) => e.name).contains(r.name)) {
        ret.add(r);
      }
    }
    if (enabledOnly) {
      ret.removeWhere((v) => !v.enabled);
    }
    return ret;
  }

  Future<void> addRuleScript(String ruleScript, {bool enabled = true}) async {
    ParsedScript result = _parseRule(rule: ruleScript, threshold: 0, modifier: 0, rolledCount: 0);
    var newRule = RuleScript(name: result.name, script: ruleScript, enabled: enabled);
    int idx = _userRules.indexWhere((r) => r.name == result.name);
    if (idx != -1) {
      _userRules[idx] = newRule;
    } else {
      _userRules.insert(0, newRule);
    }

    await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
  }

  Future<void> toggleRuleScript(String name, bool enabled) async {
    RuleScript? inUser = _userRules.firstWhereOrNull((r) => r.name == name);
    if (inUser != null) {
      inUser.enabled = enabled;
      await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
      return;
    }

    RuleScript? inDefault = defaultRules.firstWhereOrNull((r) => r.name == name);
    if (inDefault != null) {
      RuleScript toUser = RuleScript(name: inDefault.name, script: inDefault.script, enabled: true, priority: inDefault.priority);
      _userRules.add(toUser);

      await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
      return;
    }
  }

  Future<void> reorderRules(int idxFrom, int idxTo) async {
    final item = _userRules.removeAt(idxFrom);
    _userRules.insert(idxTo, item);
    await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
  }

  Future<void> removeRule(int idx) async {
    final item = _userRules.removeAt(idx);
    await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
  }


  final AppService _appService;

  RuleParser(this._dieDomain, this._rollDomain, this._appService);

  Future<void> init() async {
    _userRules = (await _appService.getSavedScripts()).map((e) => RuleScript.fromJsonString(e)).toList();
  }

  ParseResult runRule(String rule, List<GenericDie> rolls, {int threshold = 0, int modifier = 0}) {
    ParsedScript result = _parseRule(rule: rule, threshold: threshold, modifier: modifier, rolledCount: rolls.length);

    return _evaluateRule(rolls, result, threshold);
  }

  ParseResult _evaluateRule(List<GenericDie> rolls, ParsedScript result, int threshold) {
    // Check if the roll should evaluate
    List<String> rollNames = rolls.map((d) => d.dType.name).toList();
    List<String> expandedResults =
        result.roll.expand((v) {
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
    Map<GenericDie, int> rollMap = Map.fromEntries(rolls.map((r) => MapEntry(r, r.getFaceValueOrElse())));
    for (ScriptTransform transform in result.transforms) {
      rollMap = transform.transformFunction(rollMap, transform.args);
    }
    _log.fine("transformed: ${rollMap.values.toList()}");

    // apply roll aggregate
    int rollResult = result.aggregate(rollMap.values.toList());

    _log.fine("Roll Result: $rollResult");

    // determine the rolls to make a result
    Map<String, int> evaluatedRolls = Map.fromEntries(rollMap.entries.map((e) => MapEntry(e.key.dieId, e.value)));
    Map<String, int> allRolls = Map.fromEntries(rolls.map((e) => MapEntry(e.dieId, e.getFaceValueOrElse())));
    if (!passed) {
      return ParseResult(
        result: rollResult,
        allRolled: allRolls,
        rolledEvaluated: evaluatedRolls,
        ruleName: result.name,
        ruleReturn: passed,
      );
    }
    // run actions if we should evaluate
    bool ruleReturn = true;
    for (ScriptResultTarget res in result.targets) {
      if (!res.resultRange.valueIn(rollResult)) {
        continue;
      }

      switch (res.targetFunction.rtType) {
        case ResultTargetType.rule:
          ruleReturn = resultRules[res.targetFunction.action]!(args: res.targetFunction.args);
        case ResultTargetType.action:
          List<GenericDie>? actionAllDice;
          if (res.targetFunction.args.remove(allDiceKey)) {
            actionAllDice = rolls;
          }

          List<GenericDie>? actionResultDice;
          if (res.targetFunction.args.remove(resultDiceKey)) {
            actionResultDice = rollMap.keys.toList();
          }
          resultAction[res.targetFunction.action]!(
            dd: _dieDomain,
            rd: _rollDomain,
            allDice: actionAllDice,
            resultDice: actionResultDice,
            defaultDice: rollMap.keys.toList(),
            args: res.targetFunction.args,
          );
        case ResultTargetType.webhook:
      }
    }

    _log.fine("result: $ruleReturn");

    return ParseResult(
      result: rollResult,
      allRolled: allRolls,
      rolledEvaluated: evaluatedRolls,
      ruleName: result.name,
      ruleReturn: ruleReturn,
    );
  }

  ParsedScript _parseRule({required String rule, required int threshold, required int modifier, required int rolledCount}) {
    String replacedRule = rule.replaceAll(thresholdKey, threshold.toString());
    replacedRule = replacedRule.replaceAll(modifierKey, modifier.toString());
    replacedRule = replacedRule.replaceAll(rolledCountKey, rolledCount.toString());

    pp.Result<ParsedScript> result = scriptParser.parse(replacedRule);
    result.value.script = rule;
    _log.fine(result.value);
    return result.value;
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
