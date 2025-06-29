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

final pp.Parser<ScriptTransform> transformParser = [
  pp.seq3("top".toParser().map((f) => top), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3(
    "bottom".toParser().map((f) => bottom),
    pp.whitespace().star(),
    numberParser.repeatSeparated(" ".toParser(), 1, 1),
  ),
  pp.seq3(
    "equals".toParser().map((f) => equalsValue),
    pp.whitespace().star(),
    numberParser.repeatSeparated(" ".toParser(), 1, 1),
  ),
  pp.seq3(
    "match".toParser().map((f) => match),
    pp.whitespace().star(),
    numberParser.repeatSeparated(" ".toParser(), 1, 1),
  ),
  pp.seq3(
    "offset".toParser().map((f) => offset),
    pp.whitespace().star(),
    numberParser.repeatSeparated(" ".toParser(), 1, 1),
  ),
  pp.seq3("mul".toParser().map((f) => mul), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3("div".toParser().map((f) => div), pp.whitespace().star(), numberParser.repeatSeparated(" ".toParser(), 1, 1)),
  pp.seq3(
    "over".toParser().map((f) => over),
    pp.whitespace().star(),
    numberParser.repeatSeparated(" ".toParser(), 1, 1),
  ),
  pp.seq3(
    "under".toParser().map((f) => under),
    pp.whitespace().star(),
    numberParser.repeatSeparated(" ".toParser(), 1, 1),
  ),
].toChoiceParser().map3(
  (RollTransform transform, _, pp.SeparatedList<num, String> args) =>
      ScriptTransform(transformFunction: transform, args: args.elements),
);

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
