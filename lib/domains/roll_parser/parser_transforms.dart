
// transforms
import 'package:collection/collection.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

import '../../dice_sdks/dice_sdks.dart';

typedef RollTransform = Map<GenericDie, int> Function(Map<GenericDie, int> dieMap, List<num> args);

Map<GenericDie, int> top(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.sorted((e1, e2) => e1.value.compareTo(e2.value) * -1).sublist(0, args[0].toInt()));
  // return list.sorted((a, b) => a.getFaceValueOrElse().compareTo(b.getFaceValueOrElse())).sublist(0, n);
}

Map<GenericDie, int> bottom(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.sorted((e1, e2) => e1.value.compareTo(e2.value)).sublist(0, args[0].toInt()));
  // return list.sorted((a, b) => a.getFaceValueOrElse().compareTo(b.getFaceValueOrElse()) * -1).sublist(0, n).reversed.toList();
}

Map<GenericDie, int> equalsValue(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.where((e) => e.value == args[0]));
  // return list.where((i) => i.getFaceValueOrElse() == n).toList();
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
  var retMap = Map.fromEntries(counter.entries.sortedBy((e) => e.value.length).first.value.map((v) => MapEntry(v, v.getFaceValueOrElse())));
  return  retMap;
}

Map<GenericDie, int> offset(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.map((e) => MapEntry(e.key, (e.value + args[0]).round())));
  // return list.map((l) => l + n).toList();
}

Map<GenericDie, int> over(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.where((e) => args[0] <= e.value));
  // return list.map((l) => l + n).toList();
}

Map<GenericDie, int> mul(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.map((e) => MapEntry(e.key, (e.value * args[0]).round())));
  // return list.map((l) => l * n).toList();
}

Map<GenericDie, int> div(Map<GenericDie, int> dieMap, List<num> args) {
  return Map.fromEntries(dieMap.entries.map((e) => MapEntry(e.key, (e.value / args[0]).round())));
  // return list.map((l) => (l / n).round()).toList();
}
