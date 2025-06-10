import 'package:collection/collection.dart';

import 'package:petitparser/petitparser.dart' as pp;
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';


String rulePercentileSuccess = """
define is_percentile_success
for roll 1d10,1d00,*d*
apply sum
with results
on [0:!threshold) return true
on [!threshold:100] return false
""";

String ruleAdvantage = """
define advantage
for roll 2d20
apply max
with results
on [0:!threshold) return true
on [!threshold:100] return false
""";
final number = pp.digit().plus().flatten().map(int.parse);

var _defineName = pp.pattern('a-zA-Z0-9_').starString("defineName");
var _die = (["*".toParser(), pp.digit()].toChoiceParser() & 'd'.toParser() & ["*".toParser(), number].toChoiceParser()).flatten();
var _functions = [
  "sum".toParser().map((f) => sum),
  "min".toParser().map((f) => min),
  "max".toParser().map((f) => max),
  "top".toParser().map((f) => top),
  "bottom".toParser().map((f) => bottom),
  "match".toParser().map((f) => match),
].toChoiceParser();

int sum(List<int> list) {
  // return list.fold(0, (a, b) => a + b);
  return list.sum;
}
int min(List<int> list) {
  // return list.reduce((a, b) => a <= b ? a : b);
  return list.min;
}
int max(List<int> list) {
  // return list.reduce((a, b) => a <= b ? b : a);
  return list.max;
}
List<int> top(List<int> list, int n) {
  return list.sorted((a, b) => a.compareTo(b)).sublist(0, n);
}

List<int> bottom(List<int> list, int n) {
  return list.sorted((a, b) => a.compareTo(b) * -1).sublist(0, n).reversed.toList();
}

List<int> match(List<int> list, int n) {
  return list.where((i) => i == n).toList();
}

List<int> offset(List<int> list, int n) {
  return list.map((l) => l + n).toList();
}

List<int> mul(List<int> list, int n) {
  return list.map((l) => l * n).toList();
}

List<int> div(List<int> list, int n) {
  return list.map((l) => (l / n).round()).toList();
}

class DieRollContainer {
  String dName;
  int value;

  DieRollContainer(this.dName, this.value);
}

void parseRule(String rule, int? threshold, int? modifier, List<GenericDie> rolls) {
  // var parser = (pp.string("define").times(1) & pp.whitespace() & pp.pattern('a-zA-Z9-0_').star());
  var parser = pp.seq3(
    pp.seq3(pp.string("define ").times(1).flatten(), _defineName, pp.whitespace().star()),
    pp.seq4(pp.string("for roll ").times(1).flatten(), _die.plusSeparated(",".toParser()), " exactly".toParser().times(1).optional().map((e) => true), pp.whitespace().star()),
    pp.seq3(pp.string("apply ").times(1).flatten(), _functions, pp.whitespace().star()),
  ).map3((name, dieParse, apply) => <Symbol, dynamic>{
    #name: name.$2,
    #dice: dieParse.$2.elements,
    #exactly: dieParse.$3,
    #function: apply.$2
  });
  var result = parser.parse(rule);
  print(result.value);


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
  print("$rollNames, $passed");

  var rollVals = rolls.map((r) => r.getFaceValueOrElse()).toList();
  print("${result.value[#function].toString()} ${result.value[#function](rollVals)}");
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