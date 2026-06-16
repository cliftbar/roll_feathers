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

final pp.Parser<String> dieParser = (numberOrStarParser & 'd'.toParser() & numberOrStarParser).flatten().map((s) => s.trim());

class MakeSelectionDef {
  final String name;
  final String? parent;
  final List<ScriptTransform> steps;

  MakeSelectionDef({required this.name, this.parent, required this.steps});
}

class UseSelectionBlockV11 {
  final String selectionToken;
  final RollAggregate aggregate;
  final List<ScriptResultTarget> targets;

  bool get isAllDice => selectionToken == allDiceKey;

  UseSelectionBlockV11({required this.selectionToken, required this.aggregate, required this.targets});
}

class ParsedScriptV11 {
  final String name;
  final List<String> roll;
  final List<MakeSelectionDef> selections;
  final List<UseSelectionBlockV11> useBlocks;
  String? script;
  int threshold;
  int modifier;

  ParsedScriptV11({
    required this.name,
    required this.roll,
    required this.selections,
    required this.useBlocks,
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
          [_atNameParser, variableParser].toChoiceParser(),
        ).toSequenceParser().optional(),
        pp.whitespace().star(),
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

  static final pp.Parser _v11BlocksParser = [_makeSelectionParser, _useSelectionParser].toChoiceParser();

  static final pp.Parser<ParsedScriptV11> v11ScriptParser = pp
      .seq4(
        defineHeaderParser,
        pp.seq3(
          pp.string("for roll ").times(1).flatten(),
          dieParser.plusSeparated(",".toParser()),
          pp.whitespace().star(),
        ),
        _v11BlocksParser.plus(),
        pp.whitespace().star(),
      )
      .map((e) {
        final name = e.$1.$1;
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
        Logger(
          "RuleParser",
        ).finer(() => "[DSL v1.1] parsed blocks name=$name makes=${makes.length} uses=${uses.length}");
        return ParsedScriptV11(name: name, roll: rolls, selections: makes, useBlocks: uses);
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
