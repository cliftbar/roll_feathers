import 'dart:convert';

import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

final List<RuleScript> defaultRules = [
  RuleScript(name: 'd20percentiles', script: d20percentiles, enabled: false),
  RuleScript(name: 'percentiles', script: percentiles, enabled: false),
  RuleScript(name: 'doubles', script: doubles, enabled: false),
  RuleScript(name: 'advantage', script: advantage, enabled: false),
  RuleScript(name: 'standardRoll', script: standardRoll, enabled: false),
  RuleScript(name: 'minRoll', script: minRoll, enabled: false),
  RuleScript(name: 'maxRoll', script: maxRoll, enabled: false),
];

class RuleScript {
  final String name;
  final String script;
  bool enabled;
  int? priority;
  RuleScript({required this.name, required this.script, required this.enabled, this.priority = intMaxValue});

  String toJsonString() {
    return jsonEncode({
      "name": name,
      "script": script,
      "enabled": enabled,
      "priority": priority
    });
  }
  static RuleScript fromJsonString(String jsonString) {
    Map<String, dynamic> data = jsonDecode(jsonString) as Map<String, dynamic>;
    return RuleScript(name: data["name"], script: data["script"], enabled: data["enabled"], priority: data["priority"]);
  }
}

const String d20percentiles = """
define d20percentiles
for roll 2d20
transform with mul 2.5
aggregate sum
with result
on [0:10) action blink \$ALL_DICE red
on [10:25) action blink \$ALL_DICE orange
on [25:50) action blink \$ALL_DICE yellow
on [50:75) action blink \$ALL_DICE green
on [75:90) action blink \$ALL_DICE blue
on [90:*) action blink \$ALL_DICE purple
""";

const String percentiles = """
define percentiles
for roll 1d10,1d00
transform with offset \$MODIFIER
aggregate sum
with result
  on [0:10) action blink \$ALL_DICE red
  on [10:25) action blink \$ALL_DICE orange
  on [25:50) action blink \$ALL_DICE yellow
  on [50:75) action blink \$ALL_DICE green
  on [75:90) action blink \$ALL_DICE blue
  on [90:*) action blink \$ALL_DICE purple
""";

const String doubles = """
define doubles
for roll *d*
transform with match 2
aggregate sum
with result
on [*:*) action blink \$RESULT_DICE blue
""";

const String advantage = """
define advantage
for roll 2d20
transform with top 1
aggregate max
""";

const String disadvantage = """
define disadvantage
for roll 2d20
transform with bottom 1
aggregate min
""";

const String standardRoll = """
define standardRoll
for roll *d*
transform with offset \$MODIFIER
aggregate sum
with result
on [*:*] action blink \$ALL_DICE
""";

const String minRoll = """
define minRoll
for roll *d*
transform with offset \$MODIFIER
  with bottom 1
aggregate min
with result
on [*:*] action blink \$RESULT_DICE red
""";

const String maxRoll = """
define maxRoll
for roll *d*
transform with offset \$MODIFIER
  with top 1
aggregate max
with result
on [*:*] action blink \$RESULT_DICE green
""";

const String simpleTest = """
define sum
for roll 2d20
transform with offset \$MODIFIER
aggregate sum
with result
on [*:\$THRESHOLD) rule return true
on [\$THRESHOLD:*] rule return false
on [\$THRESHOLD:*] action blink \$RESULT_DICE green
""";
