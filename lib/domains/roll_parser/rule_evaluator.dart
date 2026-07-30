import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:roll_feathers/domains/roll_parser/rule_parser.dart';
import 'package:roll_feathers/domains/roll_parser/target_dtos.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/services/app_service.dart';

/// What one `use` block produced. A rule reports a single value (its `report`
/// clause), but each block computes its own aggregate over its own selection and
/// independently decides whether it fired — consumers that want the detail behind
/// the headline number read these.
class UseBlockOutput {
  /// The block's `use selection` token, e.g. `@ALL_MAX` or `$ALL_DICE`.
  final String selection;

  /// The block's own aggregate over its selection — the value its ranges tested.
  final int aggregate;

  /// Whether any `on result` range in this block matched, i.e. whether it acted.
  final bool matched;

  /// The block's selected dice, by die id.
  final Map<String, int> dice;

  const UseBlockOutput({required this.selection, required this.aggregate, required this.matched, required this.dice});

  @override
  String toString() => 'UseBlockOutput($selection agg=$aggregate matched=$matched dice=${dice.length})';
}

class ParseResult {
  /// The rule's reported value, from its required `report` clause.
  final int result;
  final Map<String, int> allRolled;

  /// Every `use` block's output, in script order — including blocks that matched
  /// nothing. [result] is the rule's single headline number; this is the detail.
  final List<UseBlockOutput> blockOutputs;

  /// The dice the rule actually acted on — the selection of the `use` block whose
  /// `on result` range matched. Falls back to all rolled dice when nothing matched.
  /// For a rule like `doubles` this is the pair, not the whole roll.
  final Map<String, int> rolledEvaluated;
  final String ruleName;
  final String? ruleDisplayName;

  /// The rule's `for roll ...` die-matcher accepted this roll. This says nothing
  /// about whether the rule produced a result — see [matchedResult].
  final bool ruleReturn;

  /// An `on result` range actually matched, so [result] is a value this rule
  /// meant to report. A rule can pass [ruleReturn] and still match no range (e.g.
  /// `doubles` on a roll with no pair, where the count aggregate is 0); callers
  /// deciding whether the rule "claims" a roll must check this, not [ruleReturn].
  final bool matchedResult;
  final int? modifier;

  ParseResult({
    required this.result,
    required this.allRolled,
    this.blockOutputs = const [],
    required this.rolledEvaluated,
    required this.ruleName,
    this.ruleDisplayName,
    required this.ruleReturn,
    this.matchedResult = false,
    this.modifier,
  });
}

class RuleEvaluation {
  final ParseResult result;
  final List<Future<void> Function()> effects;

  const RuleEvaluation({required this.result, required this.effects});

  /// Fires each effect independently, fire-and-forget. A failing effect is
  /// isolated via [onError] and never affects other effects or the caller —
  /// this is how the roll path runs side effects, after the roll is recorded.
  void fireEffects(void Function(Object error, StackTrace stack) onError) {
    for (final effect in effects) {
      effect().catchError((Object e, StackTrace st) => onError(e, st));
    }
  }
}

class _PreparedEval {
  final bool passed;
  final Map<GenericDie, int> baseMap;
  final ParsedScriptV11 result;
  final Map<String, Map<GenericDie, int>> named;

  _PreparedEval({required this.passed, required this.baseMap, required this.result, required this.named});
}

class _ActionCallArgs {
  final ActionTarget? fn;
  final List<GenericDie>? actionAllDice;
  final List<GenericDie>? actionResultDice;
  final List<String> filteredArgs;
  final List<GenericDie> defaultDice;

  _ActionCallArgs({
    required this.fn,
    required this.actionAllDice,
    required this.actionResultDice,
    required this.filteredArgs,
    required this.defaultDice,
  });
}

class RuleEvaluator {
  final Logger _log = Logger("RuleEvaluator");
  final DieDomain _dieDomain;
  final WebhookDomain _webhookDomain;

  late List<RuleScript> _userRules;
  late List<String> _ruleOrder; // canonical firing/display order (list of names)
  late Set<String> _hiddenDefaults; // names of default rules hidden by the user

  List<RuleScript> getRules({bool enabledOnly = false}) {
    final defaultByName = {for (final r in defaultRules) r.name: r};
    final userByName = {for (final r in _userRules) r.name: r};
    final result = <RuleScript>[];
    for (final name in _ruleOrder) {
      if (_hiddenDefaults.contains(name)) continue;
      final rule = userByName[name] ?? defaultByName[name];
      if (rule != null) result.add(rule);
    }
    if (enabledOnly) result.removeWhere((r) => !r.enabled);
    return result;
  }

  List<RuleScript> getHiddenDefaultRules() {
    final defaultByName = {for (final r in defaultRules) r.name: r};
    return _hiddenDefaults
        .where((name) => defaultByName.containsKey(name))
        .map((name) => defaultByName[name]!)
        .toList();
  }

  bool isUserOnlyRule(String name) {
    final defaultNames = defaultRules.map((r) => r.name).toSet();
    return _userRules.any((r) => r.name == name) && !defaultNames.contains(name);
  }

  List<String> _buildDefaultOrder() {
    final defaultNames = defaultRules.map((r) => r.name).toSet();

    final result = <String>[];
    for (final r in _userRules) {
      if (!defaultNames.contains(r.name)) result.add(r.name);
    }
    for (final r in defaultRules) {
      if (!_hiddenDefaults.contains(r.name)) result.add(r.name);
    }
    return result;
  }

  Future<void> addRuleScript(String ruleScript, {bool enabled = true}) async {
    // Throws FormatException on invalid DSL — state is not mutated before this line.
    final String name = RuleParser.parse(rule: ruleScript, threshold: 0, modifier: 0, rolledCount: 0).name;

    final prevUserRules = List<RuleScript>.from(_userRules);
    final prevRuleOrder = List<String>.from(_ruleOrder);

    final newRule = RuleScript(name: name, script: ruleScript, enabled: enabled);
    final idx = _userRules.indexWhere((r) => r.name == name);
    if (idx != -1) {
      _userRules[idx] = newRule;
    } else {
      _userRules.insert(0, newRule);
      if (!_ruleOrder.contains(name)) {
        _ruleOrder.insert(0, name);
      }
    }

    try {
      await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
      await _appService.setRuleOrder(_ruleOrder);
    } catch (e) {
      _userRules
        ..clear()
        ..addAll(prevUserRules);
      _ruleOrder
        ..clear()
        ..addAll(prevRuleOrder);
      rethrow;
    }
  }

  Future<void> toggleRuleScript(String name, bool enabled) async {
    final prevUserRules = List<RuleScript>.from(_userRules);

    final inUserIdx = _userRules.indexWhere((r) => r.name == name);
    if (inUserIdx != -1) {
      final r = _userRules[inUserIdx];
      _userRules[inUserIdx] = RuleScript(name: r.name, script: r.script, enabled: enabled, priority: r.priority);
    } else {
      final inDefault = defaultRules.firstWhereOrNull((r) => r.name == name);
      if (inDefault != null) {
        _userRules.add(
          RuleScript(name: inDefault.name, script: inDefault.script, enabled: enabled, priority: inDefault.priority),
        );
      }
    }

    try {
      await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
    } catch (e) {
      _userRules
        ..clear()
        ..addAll(prevUserRules);
      rethrow;
    }
  }

  Future<void> reorderRules(int idxFrom, int idxTo) async {
    final visible = getRules();
    if (idxFrom < 0 || idxFrom >= visible.length) return;
    if (idxTo < 0 || idxTo >= visible.length) return;

    final nameFrom = visible[idxFrom].name;
    final nameTo = visible[idxTo].name;
    final orderFrom = _ruleOrder.indexOf(nameFrom);
    final orderTo = _ruleOrder.indexOf(nameTo);
    if (orderFrom == -1 || orderTo == -1) return;

    final prevRuleOrder = List<String>.from(_ruleOrder);
    final item = _ruleOrder.removeAt(orderFrom);
    _ruleOrder.insert(orderTo, item);

    try {
      await _appService.setRuleOrder(_ruleOrder);
    } catch (e) {
      _ruleOrder
        ..clear()
        ..addAll(prevRuleOrder);
      rethrow;
    }
  }

  Future<void> removeRule(int idx) async {
    final combined = getRules();
    if (idx < 0 || idx >= combined.length) return;

    final name = combined[idx].name;
    final isDefault = defaultRules.any((r) => r.name == name);

    final prevUserRules = List<RuleScript>.from(_userRules);
    final prevRuleOrder = List<String>.from(_ruleOrder);
    final prevHiddenDefaults = Set<String>.from(_hiddenDefaults);

    if (isDefault) {
      _userRules.removeWhere((r) => r.name == name);
      _hiddenDefaults.add(name);
      _ruleOrder.remove(name);
    } else {
      _userRules.removeWhere((r) => r.name == name);
      _ruleOrder.remove(name);
    }

    try {
      await _appService.setSavedScripts(_userRules.map((e) => e.toJsonString()).toList());
      await _appService.setRuleOrder(_ruleOrder);
      await _appService.setHiddenRuleNames(_hiddenDefaults.toList());
    } catch (e) {
      _userRules
        ..clear()
        ..addAll(prevUserRules);
      _ruleOrder
        ..clear()
        ..addAll(prevRuleOrder);
      _hiddenDefaults
        ..clear()
        ..addAll(prevHiddenDefaults);
      rethrow;
    }
  }

  Future<void> unhideRule(String name) async {
    if (!_hiddenDefaults.contains(name)) return;

    final prevHiddenDefaults = Set<String>.from(_hiddenDefaults);
    final prevRuleOrder = List<String>.from(_ruleOrder);

    _hiddenDefaults.remove(name);
    _ruleOrder.add(name);

    try {
      await _appService.setHiddenRuleNames(_hiddenDefaults.toList());
      await _appService.setRuleOrder(_ruleOrder);
    } catch (e) {
      _hiddenDefaults
        ..clear()
        ..addAll(prevHiddenDefaults);
      _ruleOrder
        ..clear()
        ..addAll(prevRuleOrder);
      rethrow;
    }
  }

  final AppService _appService;

  RuleEvaluator(this._dieDomain, this._appService, this._webhookDomain);

  Future<void> init() async {
    _userRules = (await _appService.getSavedScripts()).map((e) => RuleScript.fromJsonString(e)).toList();
    _hiddenDefaults = (await _appService.getHiddenRuleNames()).toSet();
    _ruleOrder = await _appService.getRuleOrder();
    if (_ruleOrder.isEmpty) {
      _ruleOrder = _buildDefaultOrder();
    } else {
      // Append any default rules added in a later app version that aren't yet in the saved order.
      for (final r in defaultRules) {
        if (!_ruleOrder.contains(r.name) && !_hiddenDefaults.contains(r.name)) {
          _ruleOrder.add(r.name);
        }
      }
    }
  }

  RuleEvaluation evaluateRule(String rule, List<GenericDie> rolls, {int threshold = 0, int modifier = 0}) {
    final ParsedScriptV11 v11 = RuleParser.parse(
      rule: rule,
      threshold: threshold,
      modifier: modifier,
      rolledCount: rolls.length,
    );
    return _evaluateRuleV11(rolls, v11);
  }

  // ── Shared evaluation helpers ────────────────────────────────────────────────

  _PreparedEval _prepareEvaluation(List<GenericDie> rolls, ParsedScriptV11 result) {
    final rollNames = rolls.map((d) => d.dType.name).toList();
    final expandedResults =
        result.roll.expand((v) {
          if (v[0] == '*') return [v];
          final times = int.parse(v[0]);
          final dName = v.substring(1);
          return List.generate(times, (i) => dName.trim());
        }).toList();
    final passed = _checkRollConditions(expandedResults, rollNames);

    var baseMap = Map<GenericDie, int>.fromEntries(rolls.map((r) => MapEntry(r, r.getFaceValueOrElse())));
    _log.fine(() => "[DSL v1.1] Evaluating '${result.name}': rolled=${rolls.length} types=${rollNames.join(',')}");

    if (baseMap.isNotEmpty && result.script != null && result.script!.isNotEmpty) {
      final values = baseMap.values.toList();
      final gMax = values.reduce((a, b) => a > b ? a : b);
      final gMin = values.reduce((a, b) => a < b ? a : b);
      final savedThreshold = result.threshold;
      final savedModifier = result.modifier;
      final substituted = RuleParser.stripComments(result.script!)
          .replaceAll(thresholdKey, savedThreshold.toString())
          .replaceAll(modifierKey, savedModifier.toString())
          .replaceAll(maxValueKey, gMax.toString())
          .replaceAll(minValueKey, gMin.toString())
          .replaceAll(rolledAliasKey, rolls.length.toString())
          .replaceAll(rolledCountKey, rolls.length.toString());
      final reparsed = RuleParser.v11ScriptParser.parse(substituted);
      result = reparsed.value..script = substituted;
      result.threshold = savedThreshold;
      result.modifier = savedModifier;
      _log.fine(
        () =>
            "[DSL v1.1] Substituted globals: MAX=$gMax MIN=$gMin ROLLED=${rolls.length} THRESHOLD=$savedThreshold MODIFIER=$savedModifier",
      );
    }

    final named = <String, Map<GenericDie, int>>{};
    /// Merges parent selections left to right; a later parent overrides an
    /// earlier one for the same die. No parents means "all rolled dice".
    ///
    /// The override is load-bearing: a parent that is empty when it does not
    /// apply contributes nothing and leaves the earlier parent intact, which is
    /// how a rule expresses a special case without a conditional.
    Map<GenericDie, int> resolveParents(List<String> parents) {
      if (parents.isEmpty) return baseMap;
      final merged = <GenericDie, int>{};
      for (final p in parents) {
        merged.addAll(named[p] ?? baseMap);
      }
      return merged;
    }

    for (final def in result.selections) {
      var cur = Map<GenericDie, int>.of(resolveParents(def.parents));
      int stepIdx = 0;
      for (final step in def.steps) {
        cur = step.transformFunction(cur, step.args);
        _log.finer(() => "[DSL v1.1] make ${def.name} step#${stepIdx++} -> size=${cur.length}");
      }
      named[def.name] = cur;
      _log.fine(
        () =>
            "[DSL v1.1] make ${def.name} built size=${cur.length}${def.parents.isNotEmpty ? ' from ${def.parents.join(', ')}' : ''}",
      );
    }

    return _PreparedEval(passed: passed, baseMap: baseMap, result: result, named: named);
  }

  Map<GenericDie, int> _resolveSelection(
    UseSelectionBlockV11 block,
    Map<GenericDie, int> baseMap,
    Map<String, Map<GenericDie, int>> named,
  ) {
    if (block.selectionToken == allDiceKey) return baseMap;
    return named[block.selectionToken] ?? {};
  }

  List<ActionDTO> _buildCoActions(UseSelectionBlockV11 block, int aggValue) =>
      block.targets
          .where((t) => t.resultRange.valueIn(aggValue) && t.targetFunction.rtType == ResultTargetType.action)
          .map(
            (t) => ActionDTO(
              type: t.targetFunction.target,
              args: t.targetFunction.args.where((a) => a != allDiceKey && a != resultDiceKey).toList(),
            ),
          )
          .toList();

  _ActionCallArgs _buildActionCallArgs(ScriptResultTarget res, List<GenericDie> rolls, Map<GenericDie, int> selMap) {
    final localArgs = List<String>.from(res.targetFunction.args);
    final wantsAllDice = localArgs.contains(allDiceKey);
    List<GenericDie>? actionAllDice;
    List<GenericDie>? actionResultDice;
    if (wantsAllDice) {
      actionAllDice = rolls;
    } else {
      actionResultDice = selMap.keys.toList();
    }
    final filteredArgs = localArgs.where((a) => a != allDiceKey && a != resultDiceKey).toList();
    return _ActionCallArgs(
      fn: resultActionMap[res.targetFunction.target],
      actionAllDice: actionAllDice,
      actionResultDice: actionResultDice,
      filteredArgs: filteredArgs,
      defaultDice: actionResultDice ?? selMap.keys.toList(),
    );
  }

  ParseResult _buildParseResult(
    int rollResultAggregate,
    List<GenericDie> rolls,
    Map<GenericDie, int> evaluatedMap,
    String ruleName,
    bool passed, {
    String? ruleDisplayName,
    bool matchedResult = false,
    List<UseBlockOutput> blockOutputs = const [],
  }) => ParseResult(
    result: rollResultAggregate,
    allRolled: Map.fromEntries(rolls.map((e) => MapEntry(e.dieId, e.getFaceValueOrElse()))),
    blockOutputs: blockOutputs,
    rolledEvaluated: Map.fromEntries(evaluatedMap.entries.map((e) => MapEntry(e.key.dieId, e.value))),
    ruleName: ruleName,
    ruleDisplayName: ruleDisplayName,
    ruleReturn: passed,
    matchedResult: matchedResult,
  );

  RuleEvaluation _evaluateRuleV11(List<GenericDie> rolls, ParsedScriptV11 result) {
    final ctx = _prepareEvaluation(rolls, result);
    final rollTimestamp = DateTime.now().toUtc();
    final effects = <Future<void> Function()>[];
    int rollResultAggregate = 0;
    int blockIdx = 0;
    // Whether any `on result` range matched, and the selection of the block it
    // matched in — the dice the rule actually acted on. Without this a rule whose
    // die-matcher passes but whose ranges all miss (e.g. `doubles` on a roll with
    // no pair) would still report its aggregate as the roll's result.
    bool matchedResult = false;
    Map<GenericDie, int>? matchedSelection;
    final blockOutputs = <UseBlockOutput>[];
    for (final block in ctx.result.useBlocks) {
      if (!ctx.passed) break;
      final selMap = _resolveSelection(block, ctx.baseMap, ctx.named);
      final aggValue = block.aggregate(selMap.values.toList());
      _log.fine(() => "[DSL v1.1] use#${blockIdx++} sel=${block.selectionToken} size=${selMap.length} agg=$aggValue");
      final coActions = _buildCoActions(block, aggValue);

      bool blockMatched = false;
      for (final res in block.targets) {
        final rr = res.resultRange;
        _log.finer(
          () =>
              "[DSL v1.1]  check range ${rr.startInclusive ? '[' : '('}${rr.start}:${rr.end}${rr.endInclusive ? ']' : ')'} contains $aggValue -> ${rr.valueIn(aggValue)}",
        );
        if (!rr.valueIn(aggValue)) continue;
        blockMatched = true;
        // First matching block owns the reported value and the evaluated dice.
        // Assigning per-block unconditionally (as this once did) let a trailing
        // block that matched nothing overwrite the result — `highLow*` reported
        // its @ALL_MIN aggregate even when the @ALL_MAX block was the one that
        // fired.
        if (!matchedResult) {
          matchedResult = true;
          matchedSelection = selMap;
          rollResultAggregate = aggValue;
        }
        _log.fine(
          () =>
              "[DSL v1.1]  on result matched range -> queuing target ${res.targetFunction.target} args=${res.targetFunction.args.join(' ')}",
        );
        switch (res.targetFunction.rtType) {
          case ResultTargetType.action:
            final call = _buildActionCallArgs(res, rolls, selMap);
            if (call.fn != null) {
              effects.add(
                () => call.fn!(
                  dd: _dieDomain,
                  allDice: call.actionAllDice,
                  resultDice: call.actionResultDice,
                  defaultDice: call.defaultDice,
                  args: call.filteredArgs,
                ),
              );
            }
            break;
          case ResultTargetType.webhook:
            final capturedRes = res;
            final capturedAggValue = aggValue;
            final capturedSelMap = selMap;
            final capturedCoActions = coActions;
            effects.add(
              () => _webhookDomain.fireWebhook(
                url: capturedRes.targetFunction.target,
                method: capturedRes.targetFunction.args.isNotEmpty ? capturedRes.targetFunction.args[0] : 'POST',
                payload: RollResultDTO.fromRollData(
                  ruleName: ctx.result.name,
                  aggregate: capturedAggValue,
                  timestamp: rollTimestamp,
                  matchedRange: capturedRes.resultRange,
                  allDice: rolls,
                  resultDiceMap: capturedSelMap,
                  coActions: capturedCoActions,
                ),
              ),
            );
            break;
          case ResultTargetType.discord:
            final capturedRes = res;
            final capturedAggValue = aggValue;
            final capturedSelMap = selMap;
            effects.add(
              () => _webhookDomain.fireWebhook(
                url: capturedRes.targetFunction.target,
                method: 'POST',
                payload: DiscordRollDTO.fromRollData(
                  ruleName: ctx.result.name,
                  aggregate: capturedAggValue,
                  timestamp: rollTimestamp,
                  resultDiceMap: capturedSelMap,
                ),
              ),
            );
            break;
        }
      }
      blockOutputs.add(
        UseBlockOutput(
          selection: block.selectionToken,
          aggregate: aggValue,
          matched: blockMatched,
          dice: {for (final e in selMap.entries) e.key.dieId: e.value},
        ),
      );
    }
    // A `report <agg> over <selection>` clause overrides the reported value once
    // the rule has claimed the roll. Ranges still test their own block aggregate,
    // so matching behaviour is untouched — only the number the rule reports moves.
    // `rolledEvaluated` deliberately stays the acted-on selection: reporting the
    // roll total does not mean the rule acted on every die.
    final report = ctx.result.report;
    if (matchedResult) {
      final reportMap =
          report.selectionToken == allDiceKey
              ? ctx.baseMap
              : (ctx.named[report.selectionToken] ?? const <GenericDie, int>{});
      rollResultAggregate = report.aggregate(reportMap.values.toList());
      _log.fine(
        () => "[DSL v1.1] report over ${report.selectionToken} size=${reportMap.length} -> $rollResultAggregate",
      );
    }

    return RuleEvaluation(
      result: _buildParseResult(
        rollResultAggregate,
        rolls,
        matchedSelection ?? ctx.baseMap,
        ctx.result.name,
        ctx.passed,
        ruleDisplayName: ctx.result.displayName,
        matchedResult: matchedResult,
        blockOutputs: blockOutputs,
      ),
      effects: effects,
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
