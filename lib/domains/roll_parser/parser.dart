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
const String rolledAliasKey = "\$ROLLED"; // alias for total dice rolled
const String maxValueKey = "\$MAX"; // global max of initial roll values
const String minValueKey = "\$MIN"; // global min of initial roll values

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
  List<ScriptTransform> transforms;
  RollAggregate aggregate;
  List<ScriptResultTarget> targets;
  // do this better
  String? script;

  ParsedScript({
    required this.name,
    required this.roll,
    required this.transforms,
    required this.aggregate,
    required this.targets,
    this.script,
  });
}

// ===== DSL v1.1 data model =====
class MakeSelectionDef {
  final String name; // @NAME
  final String? parent; // @PARENT
  final List<ScriptTransform> steps;

  MakeSelectionDef({required this.name, this.parent, required this.steps});
}

class UseSelectionBlockV11 {
  // either @NAME or $ALL_DICE
  final String selectionToken;
  final RollAggregate aggregate;
  final List<ScriptResultTarget> targets;

  bool get isAllDice => selectionToken == allDiceKey;

  UseSelectionBlockV11({required this.selectionToken, required this.aggregate, required this.targets});
}

class ParsedScriptV11 {
  final String name;
  final List<String> roll; // like legacy
  final List<MakeSelectionDef> selections; // make selection blocks
  final List<UseSelectionBlockV11> useBlocks; // use selection blocks
  String? script;

  ParsedScriptV11({
    required this.name,
    required this.roll,
    required this.selections,
    required this.useBlocks,
    this.script,
  });
}

class RuleParser {
  // --- Helpers for v1.1 ---
  // Strip whole-line comments starting with '#'. Inline comments are NOT allowed.
  static String _stripComments(String s) {
    // Remove any line that starts with optional whitespace then '#'
    final withoutLines = s.replaceAll(RegExp(r'^\s*#.*$', multiLine: true), '');
    // Also remove trailing spaces left by deletions; keep newlines structure intact
    return withoutLines;
  }
  static final pp.Parser<String> _atNameParser =
      ("@".toParser() & wholeWordParser).flatten();

  static final pp.Parser<MakeSelectionDef> _makeSelectionParser = pp
      .seq8(
        pp.whitespace().star(),
        pp.string("make selection ").times(1).flatten(),
        _atNameParser,
        pp.whitespace().star(),
        (
          pp.string("from ").times(1).flatten(),
          [_atNameParser, variableParser].toChoiceParser(),
        ).toSequenceParser().optional(),
        pp.whitespace().star(),
        // allow zero or more steps to support "make selection @ALL from $ALL_DICE"
        transformDef.starSeparated(pp.whitespace().star()),
        pp.whitespace().star(),
      )
      .map((e) {
        final String name = e.$3;
        final String? parent = e.$5?.$2;
        final List<ScriptTransform> steps = (e.$7).elements;
        return MakeSelectionDef(name: name, parent: parent, steps: steps);
      });

  static final pp.Parser<UseSelectionBlockV11> _useSelectionParser = pp
      .seq9(
        pp.whitespace().star(),
        pp.string("use selection ").times(1).flatten(),
        [_atNameParser, variableParser].toChoiceParser(),
        pp.whitespace().star(),
        pp.string("aggregate over selection ").times(1).flatten(),
        aggregateParsers,
        pp.whitespace().star(),
        // v1.1 uses 'on result [range] ...'
        // IMPORTANT: require a non-empty separator between multiple 'on result' lines.
        // Using .star() here prevents the parser from advancing (zero-length sep),
        // so only the first target is kept. With .plus(), all subsequent targets parse.
        _v11ResultDef.plusSeparated(pp.whitespace().plus()),
        pp.whitespace().star(),
      )
      .map((e) {
        final String sel = e.$3;
        final RollAggregate agg = e.$6;
        final List<ScriptResultTarget> targets = e.$8.elements;
        // Debug: emit how many targets were parsed for this use block
        Logger("RuleParser").finer(() => "[DSL v1.1] parsed use-block targets=${targets.length} for sel=$sel");
        return UseSelectionBlockV11(selectionToken: sel, aggregate: agg, targets: targets);
      });

  // v1.1 result line: 'on result [range] action|rule ...'
  static final pp.Parser<ScriptResultTarget> _v11ResultDef = pp
      .seq7(
        "on".toParser(),
        pp.whitespace().star(),
        pp.string("result").times(1).flatten(),
        pp.whitespace().star(),
        resultRangeParser,
        pp.whitespace().star(),
        resultTarget,
      )
      .map((entry) => ScriptResultTarget(entry.$5, entry.$7));

  // Mixed-block v1.1 script parser: after header, parse a sequence of either make- or use-blocks by leading keyword
  static final pp.Parser<ParsedScriptV11> v11ScriptParser = pp
      .seq4(
        pp.seq3(pp.string("define ").times(1).flatten(), alphanumericParser, pp.whitespace().star()),
        pp.seq3(
          pp.string("for roll ").times(1).flatten(),
          dieParser.plusSeparated(",".toParser()),
          pp.whitespace().star(),
        ),
        // parse one or more blocks; we discriminate on the next keyword
        _v11BlocksParser.plus(),
        pp.whitespace().star(),
      )
      .map((e) {
        final name = e.$1.$2;
        final rolls = e.$2.$2.elements;
        final List blocks = e.$3;
        final List<MakeSelectionDef> makes = [];
        final List<UseSelectionBlockV11> uses = [];
        for (final b in blocks) {
          if (b is MakeSelectionDef) {
            makes.add(b);
          } else if (b is UseSelectionBlockV11) {
            uses.add(b);
          }
        }
        // Debug: how many blocks parsed
        Logger("RuleParser").finer(() => "[DSL v1.1] parsed blocks name=$name makes=${makes.length} uses=${uses.length}");
        return ParsedScriptV11(name: name, roll: rolls, selections: makes, useBlocks: uses);
      });

  // One v1.1 block, chosen by leading keyword
  static final pp.Parser _v11BlocksParser = [
    _makeSelectionParser,
    _useSelectionParser,
  ].toChoiceParser();
  static final pp.Parser<ParsedScript> scriptParser = pp
      .seq5(
        pp.seq3(pp.string("define ").times(1).flatten(), alphanumericParser, pp.whitespace().star()),
        pp.seq3(
          pp.string("for roll ").times(1).flatten(),
          dieParser.plusSeparated(",".toParser()),
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
    // Interpret idx as an index into the combined visible rules list (user + defaults).
    // Deleting a default rule should "reset" it, which effectively means removing any
    // user override/saved copy. So we locate by name in _userRules and remove that entry.
    final List<RuleScript> combined = getRules();
    if (idx < 0 || idx >= combined.length) {
      return; // out of range; nothing to remove
    }
    final String name = combined[idx].name;
    final int userIdx = _userRules.indexWhere((r) => r.name == name);
    if (userIdx != -1) {
      _userRules.removeAt(userIdx);
      await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
    } else {
      // No user-defined rule with this name; it's a built-in default with no override.
      // Nothing to persist for removal; treat as a no-op reset.
      return;
    }
  }


  final AppService _appService;

  RuleParser(this._dieDomain, this._rollDomain, this._appService);

  Future<void> init() async {
    _userRules = (await _appService.getSavedScripts()).map((e) => RuleScript.fromJsonString(e)).toList();
  }

  ParseResult runRule(String rule, List<GenericDie> rolls, {int threshold = 0, int modifier = 0}) {
    // v1.1 only: parse and evaluate using the new grammar
    final ParsedScriptV11 v11 = _parseRuleV11(rule: rule, threshold: threshold, modifier: modifier, rolledCount: rolls.length);
    return _evaluateRuleV11(rolls, v11);
  }

  Future<ParseResult> runRuleAsync(String rule, List<GenericDie> rolls, {int threshold = 0, int modifier = 0}) async {
    final ParsedScriptV11 v11 = _parseRuleV11(rule: rule, threshold: threshold, modifier: modifier, rolledCount: rolls.length);
    return await _evaluateRuleV11Async(rolls, v11);
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
          break;
        case ResultTargetType.action:
          List<GenericDie>? actionAllDice;
          if (res.targetFunction.args.remove(allDiceKey)) {
            actionAllDice = rolls;
          }

          List<GenericDie>? actionResultDice;
          if (res.targetFunction.args.remove(resultDiceKey)) {
            actionResultDice = rollMap.keys.toList();
          }
          final fn = resultAction[res.targetFunction.action];
          if (fn != null) {
            fn(
              dd: _dieDomain,
              rd: _rollDomain,
              allDice: actionAllDice,
              resultDice: actionResultDice,
              defaultDice: rollMap.keys.toList(),
              args: res.targetFunction.args,
            );
          }
          break;
        case ResultTargetType.webhook:
          break;
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
    // provide total rolled count under both $ROLLED_COUNT and $ROLLED
    replacedRule = replacedRule.replaceAll(rolledCountKey, rolledCount.toString());
    replacedRule = replacedRule.replaceAll(rolledAliasKey, rolledCount.toString());

    pp.Result<ParsedScript> result = scriptParser.parse(replacedRule);
    result.value.script = rule;
    _log.fine(result.value);
    return result.value;
  }

  ParsedScriptV11 _parseRuleV11({required String rule, required int threshold, required int modifier, required int rolledCount}) {
    String replacedRule = rule.replaceAll(thresholdKey, threshold.toString());
    replacedRule = replacedRule.replaceAll(modifierKey, modifier.toString());
    // compute global max/min from the incoming rolls for substitution below
    // Note: we don't have the rolls here, so we only substitute $ROLLED and defer $MAX/$MIN to evaluation time path.
    // For v1.1 we will also substitute $ROLLED alias here.
    replacedRule = replacedRule.replaceAll(rolledCountKey, rolledCount.toString());
    replacedRule = replacedRule.replaceAll(rolledAliasKey, rolledCount.toString());
    // strip comments to allow inline '#' comments in scripts
    replacedRule = _stripComments(replacedRule);

    final pp.Result<ParsedScriptV11> res = v11ScriptParser.parse(replacedRule);
    final ParsedScriptV11 value = res.value;
    value.script = rule;
    // DEBUG LOGS: summarize parsed structure
    try {
      _log.fine(() =>
          "[DSL v1.1] Parsed rule '${value.name}': rolls=${value.roll.join(',')} makeBlocks=${value.selections.length} useBlocks=${value.useBlocks.length}");
    } catch (_) {}
    return value;
  }

  ParseResult _evaluateRuleV11(List<GenericDie> rolls, ParsedScriptV11 result) {
    // Check roll pattern first
    List<String> rollNames = rolls.map((d) => d.dType.name).toList();
    List<String> expandedResults = result.roll
        .expand((v) {
          if (v[0] == "*") {
            return [v];
          } else {
            int times = int.parse(v[0]);
            String dName = v.substring(1);
            return List.generate(times, (i) => dName.trim());
          }
        })
        .toList();
    bool passed = _checkRollConditions(expandedResults, rollNames);

    Map<GenericDie, int> baseMap = Map.fromEntries(rolls.map((r) => MapEntry(r, r.getFaceValueOrElse())));
    _log.fine(() => "[DSL v1.1] Evaluating '${result.name}': rolled=${rolls.length} types=${rollNames.join(',')}");
    // Compute global min/max of the initial values and apply substitution to the script for this evaluation.
    if (baseMap.isNotEmpty && (result.script != null && result.script!.isNotEmpty)) {
      final values = baseMap.values.toList();
      final int gMax = values.reduce((a, b) => a > b ? a : b);
      final int gMin = values.reduce((a, b) => a < b ? a : b);
      // Perform a one-time substitution on the script text so transforms like match [$MAX:$MAX] work
      final String substituted = _stripComments(result.script!)
          .replaceAll(maxValueKey, gMax.toString())
          .replaceAll(minValueKey, gMin.toString())
          .replaceAll(rolledAliasKey, rolls.length.toString())
          .replaceAll(rolledCountKey, rolls.length.toString());
      // Re-parse the script with substituted values to rebuild selections/blocks accordingly.
      final pp.Result<ParsedScriptV11> reparsed = v11ScriptParser.parse(substituted);
      result = reparsed.value..script = substituted;
      _log.fine(() => "[DSL v1.1] Substituted globals: MAX=$gMax MIN=$gMin ROLLED=${rolls.length}");
    }

    // Build named selections
    Map<String, Map<GenericDie, int>> named = {};
    // Helper to get parent map
    Map<GenericDie, int> resolveParent(String? parent) {
      if (parent == null) return baseMap;
      return named[parent] ?? baseMap;
    }

    for (final def in result.selections) {
      Map<GenericDie, int> cur = Map.of(resolveParent(def.parent));
      int stepIdx = 0;
      for (final step in def.steps) {
        cur = step.transformFunction(cur, step.args);
        _log.finer(() => "[DSL v1.1] make ${def.name} step#${stepIdx++} -> size=${cur.length}");
      }
      named[def.name] = cur;
      _log.fine(() => "[DSL v1.1] make ${def.name} built size=${cur.length}${def.parent != null ? ' from ${def.parent!}' : ''}");
    }

    int rollResultAggregate = 0; // not used globally in v1.1, but kept for reporting

    // Evaluate use blocks
    // Evaluate each block independently; no short-circuiting between blocks
    int blockIdx = 0;
    for (final block in result.useBlocks) {
      if (!passed) break; // if pattern fails, do nothing
      Map<GenericDie, int> selMap;
      if (block.selectionToken == allDiceKey) {
        selMap = baseMap;
      } else {
        selMap = named[block.selectionToken] ?? {};
      }
      // aggregate over selection values
      final int aggValue = block.aggregate(selMap.values.toList());
      rollResultAggregate = aggValue;
      _log.fine(() => "[DSL v1.1] use#${blockIdx++} sel=${block.selectionToken} size=${selMap.length} agg=$aggValue");

      for (final res in block.targets) {
        if (!res.resultRange.valueIn(aggValue)) continue;
        _log.fine(() => "[DSL v1.1]  on result matched range -> firing target ${res.targetFunction.action} args=${res.targetFunction.args.join(' ')}");
        switch (res.targetFunction.rtType) {
          case ResultTargetType.rule:
            // v1.1: rule returns are disabled; ignore silently
            continue;
          case ResultTargetType.action:
            // immutable args handling
            final localArgs = List<String>.from(res.targetFunction.args);
            // Handle special selection tokens for action target resolution
            final bool wantsAllDice = localArgs.contains(allDiceKey);
            final bool wantsResultDice = localArgs.contains(resultDiceKey);
            List<GenericDie>? actionAllDice;
            List<GenericDie>? actionResultDice;

            if (wantsAllDice) {
              // Caller explicitly requests all dice; provide via allDice and
              // avoid passing resultDice to ensure action uses allDice path.
              actionAllDice = rolls;
              actionResultDice = null;
            } else {
              // Default v1.1: selection of this block
              actionResultDice = selMap.keys.toList();
            }

            final filteredArgs = localArgs
                .where((a) => a != allDiceKey && a != resultDiceKey)
                .toList();
            final fn = resultAction[res.targetFunction.action];
            if (fn != null) {
              fn(
                dd: _dieDomain,
                rd: _rollDomain,
                allDice: actionAllDice,
                resultDice: actionResultDice,
                defaultDice: actionResultDice ?? selMap.keys.toList(),
                args: filteredArgs,
              );
            }
            break;
          case ResultTargetType.webhook:
            break;
        }
      }
    }

    return ParseResult(
      result: rollResultAggregate,
      allRolled: Map.fromEntries(rolls.map((e) => MapEntry(e.dieId, e.getFaceValueOrElse()))),
      rolledEvaluated: Map.fromEntries(baseMap.entries.map((e) => MapEntry(e.key.dieId, e.value))),
      ruleName: result.name,
      ruleReturn: true,
    );
  }

  Future<ParseResult> _evaluateRuleV11Async(List<GenericDie> rolls, ParsedScriptV11 result) async {
    // Check roll pattern first
    List<String> rollNames = rolls.map((d) => d.dType.name).toList();
    List<String> expandedResults = result.roll
        .expand((v) {
          if (v[0] == "*") {
            return [v];
          } else {
            int times = int.parse(v[0]);
            String dName = v.substring(1);
            return List.generate(times, (i) => dName.trim());
          }
        })
        .toList();
    bool passed = _checkRollConditions(expandedResults, rollNames);

    Map<GenericDie, int> baseMap = Map.fromEntries(rolls.map((r) => MapEntry(r, r.getFaceValueOrElse())));
    _log.fine(() => "[DSL v1.1] Evaluating (async) '${result.name}': rolled=${rolls.length} types=${rollNames.join(',')}");

    // Apply $MAX/$MIN/$ROLLED substitutions for this evaluation, mirroring sync path
    if (baseMap.isNotEmpty && (result.script != null && result.script!.isNotEmpty)) {
      final values = baseMap.values.toList();
      final int gMax = values.reduce((a, b) => a > b ? a : b);
      final int gMin = values.reduce((a, b) => a < b ? a : b);
      final String substituted = _stripComments(result.script!)
          .replaceAll(maxValueKey, gMax.toString())
          .replaceAll(minValueKey, gMin.toString())
          .replaceAll(rolledAliasKey, rolls.length.toString())
          .replaceAll(rolledCountKey, rolls.length.toString());
      final pp.Result<ParsedScriptV11> reparsed = v11ScriptParser.parse(substituted);
      result = reparsed.value..script = substituted;
      _log.fine(() => "[DSL v1.1] Substituted globals (async): MAX=$gMax MIN=$gMin ROLLED=${rolls.length}");
    }

    // Build named selections
    Map<String, Map<GenericDie, int>> named = {};
    Map<GenericDie, int> resolveParent(String? parent) {
      if (parent == null) return baseMap;
      return named[parent] ?? baseMap;
    }

    for (final def in result.selections) {
      Map<GenericDie, int> cur = Map.of(resolveParent(def.parent));
      int stepIdx = 0;
      for (final step in def.steps) {
        cur = step.transformFunction(cur, step.args);
        _log.finer(() => "[DSL v1.1] (async) make ${def.name} step#${stepIdx++} -> size=${cur.length}");
      }
      named[def.name] = cur;
      _log.fine(() => "[DSL v1.1] (async) make ${def.name} built size=${cur.length}${def.parent != null ? ' from ${def.parent!}' : ''}");
    }

    int rollResultAggregate = 0;

    int blockIdx = 0;
    for (final block in result.useBlocks) {
      if (!passed) break;
      Map<GenericDie, int> selMap;
      if (block.selectionToken == allDiceKey) {
        selMap = baseMap;
      } else {
        selMap = named[block.selectionToken] ?? {};
      }
      final int aggValue = block.aggregate(selMap.values.toList());
      rollResultAggregate = aggValue;
      _log.fine(() => "[DSL v1.1] (async) use#${blockIdx++} sel=${block.selectionToken} size=${selMap.length} agg=$aggValue");

      for (final res in block.targets) {
        // Debug: log range evaluation details
        final rr = res.resultRange;
        _log.finer(() => "[DSL v1.1]  (async) check range ${rr.startInclusive ? '[' : '('}${rr.start}:${rr.end}${rr.endInclusive ? ']' : ')'} contains $aggValue -> ${rr.valueIn(aggValue)}");
        if (!rr.valueIn(aggValue)) continue;
        _log.fine(() => "[DSL v1.1]  (async) on result matched range -> firing target ${res.targetFunction.action} args=${res.targetFunction.args.join(' ')}");
        switch (res.targetFunction.rtType) {
          case ResultTargetType.rule:
            continue;
          case ResultTargetType.action:
            final localArgs = List<String>.from(res.targetFunction.args);
            // Handle special selection tokens for action target resolution
            final bool wantsAllDice = localArgs.contains(allDiceKey);
            final bool wantsResultDice = localArgs.contains(resultDiceKey);
            List<GenericDie>? actionAllDice;
            List<GenericDie>? actionResultDice;

            if (wantsAllDice) {
              actionAllDice = rolls;
              actionResultDice = null; // ensure action uses allDice path
            } else {
              actionResultDice = selMap.keys.toList();
            }

            final filteredArgs = localArgs
                .where((a) => a != allDiceKey && a != resultDiceKey)
                .toList();
            final fn = resultAction[res.targetFunction.action];
            if (fn != null) {
              await fn(
                dd: _dieDomain,
                rd: _rollDomain,
                allDice: actionAllDice,
                resultDice: actionResultDice,
                defaultDice: actionResultDice ?? selMap.keys.toList(),
                args: filteredArgs,
              );
            }
            break;
          case ResultTargetType.webhook:
            break;
        }
      }
    }

    return ParseResult(
      result: rollResultAggregate,
      allRolled: Map.fromEntries(rolls.map((e) => MapEntry(e.dieId, e.getFaceValueOrElse()))),
      rolledEvaluated: Map.fromEntries(baseMap.entries.map((e) => MapEntry(e.key.dieId, e.value))),
      ruleName: result.name,
      ruleReturn: true,
    );
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
