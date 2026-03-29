// transforms
import 'package:collection/collection.dart';
import 'package:petitparser/parser.dart' as pp;

import '../../dice_sdks/dice_sdks.dart';
import 'parser_definitions.dart';

typedef RollTransform = Map<GenericDie, int> Function(Map<GenericDie, int> dieMap, List<num> args);

class ScriptTransform {
  RollTransform transformFunction;
  List<num> args;

  ScriptTransform({required this.transformFunction, required this.args});
}

// local bounds to support interval parsing without extra deps
const int _intMaxValue = 9000000000000000;
const int _intMinValue = -9000000000000000;

// Interval helpers (inclusive/exclusive) reused for `match [a:b]`
final pp.Parser<bool> _startIntervalClosedParser =
    ["[".toParser().map((_) => true), "(".toParser().map((_) => false)].toChoiceParser();
final pp.Parser<bool> _endIntervalClosedParser =
    ["]".toParser().map((_) => true), ")".toParser().map((_) => false)].toChoiceParser();

final pp.Parser<List<int>> _valueRangeParser = pp
    .seq9<bool, void, num, void, String, void, num, void, bool>(
      _startIntervalClosedParser,
      pp.whitespace().star(),
      [numberParser, "*".toParser().map((e) => _intMinValue)].toChoiceParser(),
      pp.whitespace().star(),
      ":".toParser(),
      pp.whitespace().star(),
      [numberParser, "*".toParser().map((e) => _intMaxValue)].toChoiceParser(),
      pp.whitespace().star(),
      _endIntervalClosedParser,
    )
    .map((e) {
  final bool startInc = e.$1;
  final num minVal = e.$3;
  final num maxVal = e.$7;
  final bool endInc = e.$9;
  // convert to effective closed interval on integers
  int start = minVal.round();
  int end = maxVal.round();
  int effStart = startInc ? start : start + 1;
  int effEnd = endInc ? end : end - 1;
  return [effStart, effEnd];
});

final pp.Parser<ScriptTransform> transformParser = [
  pp
      .seq3("top".toParser().map((_) => top), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  pp
      .seq3("bottom".toParser().map((_) => bottom), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  pp
      .seq3("equals".toParser().map((_) => equalsValue), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  // match N (existing semantics for doubles/matches)
  pp
      .seq3("match".toParser().map((_) => match), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  // match [a:b] (new interval semantics)
  pp
      .seq3("match".toParser(), pp.whitespace().star(), _valueRangeParser)
      .map((e) {
    final List<int> range = e.$3;
    return ScriptTransform(transformFunction: matchInterval, args: [range[0], range[1]]);
  }),
  // dupes [a:b] (same-face multiplicity filter over current selection)
  pp
      .seq3("dupes".toParser(), pp.whitespace().star(), _valueRangeParser)
      .map((e) {
    final List<int> range = e.$3;
    return ScriptTransform(transformFunction: dupesInterval, args: [range[0], range[1]]);
  }),
  pp
      .seq3("offset".toParser().map((_) => offset), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  pp
      .seq3("mul".toParser().map((_) => mul), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  pp
      .seq3("div".toParser().map((_) => div), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  pp
      .seq3("over".toParser().map((_) => over), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
  pp
      .seq3("under".toParser().map((_) => under), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1))
      .map3((RollTransform f, _, pp.SeparatedList<num, String> a) =>
          ScriptTransform(transformFunction: f, args: a.elements)),
].toChoiceParser();

final pp.Parser<ScriptTransform> transformDef = pp
    .seq4(pp.string("with").times(1).flatten(), pp.whitespace().star(), transformParser, pp.whitespace().star())
    .map((entry) => entry.$3);

Map<GenericDie, int> top(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(
    dieMap.entries.sorted((e1, e2) => e1.value.compareTo(e2.value) * -1).sublist(0, args[0].toInt()),
  );
}

Map<GenericDie, int> bottom(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.sorted((e1, e2) => e1.value.compareTo(e2.value)).sublist(0, args[0].toInt()));
}

Map<GenericDie, int> equalsValue(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.where((e) => e.value == args[0]));
}

Map<GenericDie, int> match(Map<GenericDie, int> dieMap, List<num> args) {
  Map<int, List<GenericDie>> counter = {};
  for (var entry in dieMap.entries) {
    counter.putIfAbsent(entry.value, () => []).add(entry.key);
  }
  counter.removeWhere((k, v) => v.length < args[0]);
  if (counter.isEmpty) {
    return {};
  }
  var retMap = Map.fromEntries(
    counter.entries.sortedBy((e) => e.value.length).first.value.map((v) => MapEntry(v, v.getFaceValueOrElse())),
  );
  return retMap;
}

Map<GenericDie, int> offset(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.map((e) => MapEntry(e.key, (e.value + args[0]).round())));
}

Map<GenericDie, int> over(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.where((e) => args[0] < e.value));
}

Map<GenericDie, int> under(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.where((e) => e.value < args[0]));
}

Map<GenericDie, int> mul(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.map((e) => MapEntry(e.key, (e.value * args[0]).round())));
}

Map<GenericDie, int> div(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.map((e) => MapEntry(e.key, (e.value / args[0]).round())));
}

// New interval-based match: keep values between args[0]..args[1] inclusive
Map<GenericDie, int> matchInterval(Map<GenericDie, int> dieMap, List<num> args) {
  int start = args[0].round();
  int end = args[1].round();
  return Map.fromEntries(dieMap.entries.where((e) => start <= e.value && e.value <= end));
}

// dupesInterval: keep all dice that belong to any face bucket whose multiplicity
// (count of equal face values within current selection) is within [start..end] inclusive.
// Example: with dupes [2:*] keeps all dice that are part of doubles, triples, quads, etc.
Map<GenericDie, int> dupesInterval(Map<GenericDie, int> dieMap, List<num> args) {
  int start = args[0].round();
  int end = args[1].round();
  if (dieMap.isEmpty) return {};

  // Build histogram of face values -> list of dice
  final Map<int, List<MapEntry<GenericDie, int>>> buckets = {};
  for (final e in dieMap.entries) {
    buckets.putIfAbsent(e.value, () => []).add(e);
  }

  // Determine which face values meet the multiplicity condition
  final Set<int> keepFaces = {};
  buckets.forEach((face, entries) {
    final int c = entries.length;
    if (start <= c && c <= end) {
      keepFaces.add(face);
    }
  });

  if (keepFaces.isEmpty) return {};

  // Keep all dice whose (current) face value is in keepFaces
  return Map.fromEntries(dieMap.entries.where((e) => keepFaces.contains(e.value)));
}
