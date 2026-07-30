import 'package:logging/logging.dart';
import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/domains/roll_parser/parser_aggregates.dart';
import 'package:roll_feathers/domains/roll_parser/parser_definitions.dart';
import 'package:roll_feathers/domains/roll_parser/parser_transforms.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

const String modifierKey = "\$MODIFIER";
const String thresholdKey = "\$THRESHOLD";
const String allDiceKey = "\$ALL_DICE";
const String resultDiceKey = "\$RESULT_DICE";
const String rolledCountKey = "\$ROLLED_COUNT";
const String rolledAliasKey = "\$ROLLED";
const String maxValueKey = "\$MAX";
const String minValueKey = "\$MIN";

final pp.Parser<String> dieParser = (numberOrStarParser & 'd'.toParser() & numberOrStarParser).flatten().map(
  (s) => s.trim(),
);

class MakeSelectionDef {
  final String name;

  /// Parent selections, merged left to right with **later parents overriding
  /// earlier ones** on the same die. Empty means "start from all rolled dice".
  ///
  /// The override is what lets a rule express a special case without a
  /// conditional: a parent that is empty when it does not apply contributes
  /// nothing, and the earlier parent passes through untouched.
  final List<String> parents;
  final List<ScriptTransform> steps;

  MakeSelectionDef({required this.name, this.parents = const [], required this.steps});
}

class UseSelectionBlockV11 {
  final String selectionToken;
  final RollAggregate aggregate;
  final List<ScriptResultTarget> targets;

  bool get isAllDice => selectionToken == allDiceKey;

  UseSelectionBlockV11({required this.selectionToken, required this.aggregate, required this.targets});
}

/// An optional rule-level `report <agg> over <selection>` clause.
///
/// A `use` block's aggregate does two jobs at once: it decides whether an
/// `on result` range matches, and it becomes the rule's reported value. Those
/// are not always the same number — `highLow*` must *match* on max/min to pick
/// which dice to blink, but should *report* the roll's total. This clause
/// separates them: ranges keep testing the block aggregate, while the reported
/// value comes from here.
class ReportDef {
  final RollAggregate aggregate;
  final String selectionToken;

  ReportDef({required this.aggregate, required this.selectionToken});
}

class ParsedScriptV11 {
  final String name;
  final String? displayName;
  final List<String> roll;
  final List<MakeSelectionDef> selections;
  final List<UseSelectionBlockV11> useBlocks;

  /// Required, and written last: the single value the roll is recorded as.
  final ReportDef report;
  String? script;
  int threshold;
  int modifier;

  ParsedScriptV11({
    required this.name,
    this.displayName,
    required this.roll,
    required this.selections,
    required this.useBlocks,
    required this.report,
    this.script,
    this.threshold = 0,
    this.modifier = 0,
  });
}

class RuleParser {
  static final Logger _log = Logger("RuleParser");

  // Strip whole-line comments starting with '#'. Inline comments are NOT allowed.
  static String stripComments(String s) {
    final withoutLines = s.replaceAll(RegExp(r'^\s*#.*$', multiLine: true), '');
    return withoutLines;
  }

  static final pp.Parser<String> _atNameParser = ("@".toParser() & wholeWordParser).flatten();

  static final pp.Parser<MakeSelectionDef> _makeSelectionParser = pp
      .seq8(
        pp.whitespace().star(),
        pp.string("make selection ").times(1).flatten(),
        _atNameParser,
        pp.whitespace().star(),
        (
          pp.string("from ").times(1).flatten(),
          [_atNameParser, variableParser]
              .toChoiceParser()
              .plusSeparated(pp.seq3(pp.whitespace().star(), ",".toParser(), pp.whitespace().star())),
        ).toSequenceParser().optional(),
        pp.whitespace().star(),
        transformDef.starSeparated(pp.whitespace().star()),
        pp.whitespace().star(),
      )
      .map((e) {
        final String name = e.$3;
        final List<String> parents = e.$5?.$2.elements ?? const <String>[];
        final List<ScriptTransform> steps = (e.$7).elements;
        return MakeSelectionDef(name: name, parents: parents, steps: steps);
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
        _v11ResultDef.plusSeparated(pp.whitespace().plus()),
        pp.whitespace().star(),
      )
      .map((e) {
        final String sel = e.$3;
        final RollAggregate agg = e.$6;
        final List<ScriptResultTarget> targets = e.$8.elements;
        Logger("RuleParser").finer(() => "[DSL v1.1] parsed use-block targets=${targets.length} for sel=$sel");
        return UseSelectionBlockV11(selectionToken: sel, aggregate: agg, targets: targets);
      });

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

  /// Cheap textual check for the presence of a `report` clause, for diagnostics
  /// that need to distinguish "no report clause" from any other parse failure.
  /// Not a substitute for parsing — it says the clause is there, not that it is
  /// well-formed or correctly placed.
  static final RegExp reportClausePattern = RegExp(r'^\s*report\s+\w+\s+over\s+\S+', multiLine: true);

  /// `report <aggregate> over <selection>` — e.g. `report sum over $ALL_DICE`.
  static final pp.Parser<ReportDef> _reportParser = pp
      .seq7(
        pp.whitespace().star(),
        pp.string("report ").times(1).flatten(),
        aggregateParsers,
        pp.whitespace().star(),
        pp.string("over ").times(1).flatten(),
        [_atNameParser, variableParser].toChoiceParser(),
        pp.whitespace().star(),
      )
      .map((e) => ReportDef(aggregate: e.$3, selectionToken: e.$6));

  static final pp.Parser _v11BlocksParser = [_makeSelectionParser, _useSelectionParser].toChoiceParser();

  /// `report` is required and must be the last clause in a rule — it is the single
  /// value the roll is recorded as, so every rule has to say what it reports.
  static final pp.Parser<ParsedScriptV11> v11ScriptParser = pp
      .seq5(
        defineHeaderParser,
        pp.seq3(
          pp.string("for roll ").times(1).flatten(),
          dieParser.plusSeparated(",".toParser()),
          pp.whitespace().star(),
        ),
        _v11BlocksParser.plus(),
        _reportParser,
        pp.whitespace().star(),
      )
      .map((e) {
        final name = e.$1.$1;
        final displayName = e.$1.$2;
        final rolls = e.$2.$2.elements;
        final List blocks = e.$3;
        final ReportDef report = e.$4;
        final List<MakeSelectionDef> makes = [];
        final List<UseSelectionBlockV11> uses = [];
        for (final b in blocks) {
          if (b is MakeSelectionDef) {
            makes.add(b);
          } else if (b is UseSelectionBlockV11) {
            uses.add(b);
          }
        }
        Logger("RuleParser").finer(
          () =>
              "[DSL v1.1] parsed blocks name=$name makes=${makes.length} uses=${uses.length} "
              "report=${report.selectionToken}",
        );
        return ParsedScriptV11(
          name: name,
          displayName: displayName,
          roll: rolls,
          selections: makes,
          useBlocks: uses,
          report: report,
        );
      });

  static ParsedScriptV11 parse({
    required String rule,
    required int threshold,
    required int modifier,
    required int rolledCount,
  }) {
    String replacedRule = rule.replaceAll(thresholdKey, threshold.toString());
    replacedRule = replacedRule.replaceAll(modifierKey, modifier.toString());
    replacedRule = replacedRule.replaceAll(rolledCountKey, rolledCount.toString());
    replacedRule = replacedRule.replaceAll(rolledAliasKey, rolledCount.toString());
    // $MAX/$MIN depend on the dice and are only known at evaluation time, where
    // `_prepareEvaluation` substitutes them and reparses. This structural parse
    // just needs the shape, so stand them in with a placeholder — otherwise the
    // block they appear in fails to parse and, since `report` is required
    // immediately after the blocks, the whole rule is rejected.
    replacedRule = replacedRule.replaceAll(maxValueKey, '0').replaceAll(minValueKey, '0');
    replacedRule = stripComments(replacedRule);

    final pp.Result<ParsedScriptV11> res = v11ScriptParser.parse(replacedRule);
    final ParsedScriptV11 value = res.value;
    value.script = rule;
    value.threshold = threshold;
    value.modifier = modifier;
    try {
      _log.fine(
        () =>
            "[DSL v1.1] Parsed rule '${value.name}': rolls=${value.roll.join(',')} makeBlocks=${value.selections.length} useBlocks=${value.useBlocks.length}",
      );
    } catch (_) {}
    return value;
  }
}
