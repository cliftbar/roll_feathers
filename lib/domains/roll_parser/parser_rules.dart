import 'dart:convert';

import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

final List<RuleScript> defaultRules = [
  RuleScript(name: 'Percentiles (2d20)', script: d20percentiles, enabled: false),
  RuleScript(name: 'Percentiles (1d10,1d100)', script: percentiles, enabled: false),
  RuleScript(name: 'Doubles', script: doubles, enabled: false),
  RuleScript(name: 'Duplicates', script: nDupes, enabled: false),
  RuleScript(name: 'Advantage', script: advantage, enabled: false),
  RuleScript(name: 'Disadvantage', script: disadvantage, enabled: false),
  RuleScript(name: 'Basic Blink', script: standardRoll, enabled: true),
  RuleScript(name: 'Max (with Modifier)', script: maxWithModifier, enabled: false),
  RuleScript(name: 'All Above Threshold', script: allAboveThreshold, enabled: false),
  RuleScript(name: 'Avg Pass/Fail (d10)', script: averagePassFailD10, enabled: false),
  RuleScript(name: 'High/Low/Tie All', script: highLowAllTies, enabled: false),
  RuleScript(name: 'High/Low/Tie Single', script: highLowTiesSingle, enabled: false),
  RuleScript(name: 'High/Low', script: highLowSinglePreferMax, enabled: false),
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
define d20percentiles for roll 2d20

  make selection @ALL
    with match [*:*]
    with mul 2.5

  use selection @ALL
    aggregate over selection sum
    on result [0:10)  action blink red
    on result [10:25) action blink orange
    on result [25:50) action blink yellow
    on result [50:75) action blink green
    on result [75:90) action blink blue
    on result [90:99) action blink purple
    on result [99:*)  action sequence 1 red orange green blue violet
""";

const String percentiles = """
define percentiles for roll 1d10,1d00

  use selection \$ALL_DICE
    aggregate over selection sum
    on result [0:10)  action blink red
    on result [10:25) action blink orange
    on result [25:50) action blink yellow
    on result [50:75) action blink green
    on result [75:90) action blink blue
    on result [90:99) action blink purple
    on result [99:*)  action sequence 1 red orange green blue violet
""";

const String doubles = """
define doubles for roll *d*

  make selection @DUPE2
    with dupes [2:2]

  use selection @DUPE2
    aggregate over selection count
    on result [1:*] action blink blue
""";

const String nDupes = """
define nDupes for roll *d*

  make selection @NDUPE
    with dupes [\$THRESHOLD:\$THRESHOLD]

  use selection @NDUPE
    aggregate over selection count
    on result [1:*] action blink blue
""";

const String advantage = """
define advantage for roll 2d20

  make selection @TOP
    with top 1

  use selection @TOP
    aggregate over selection max
    on result [*:*] action blink green
""";

const String disadvantage = """
define disadvantage for roll 2d20

  make selection @BOT
    with bottom 1

  use selection @BOT
    aggregate over selection min
    on result [*:*] action blink red
""";

const String standardRoll = """
define standardRoll for roll *d*

  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
""";

const String maxWithModifier = """
define maxWithModifier for roll *d*
# blink one die with the highest value after applying the modifier

  make selection @ALL_MOD
    from \$ALL_DICE
    with offset \$MODIFIER
    with top 1

  use selection @ALL_MOD
    aggregate over selection max
    on result [*:*] action blink blue
""";

const String allAboveThreshold = """
define allAboveThreshold for roll *d*

  make selection @ALL_THRESH
    with match [*:*]
    with over \$THRESHOLD

  use selection @ALL_THRESH
    aggregate over selection count
    on result [1:*] action blink green
""";

const String averagePassFailD10 = """
define averagePassFailD10 for roll *d10

  make selection @ALL
    with match [*:*]

  use selection @ALL
    aggregate over selection avg
    on result [*:5] action blink red
    on result (5:10] action blink blue
""";

const String highLowAllTies = """
define highLowAllTiesExclusive for roll *d*
# Blink all High and Low dice, and if all are Tied

  make selection @ALL_MAX
    with match [\$MAX:\$MAX]

  make selection @ALL_MIN
    with match [\$MIN:\$MIN]

  make selection @DUPE_ANY
    with dupes [2:*]

  # All-equal → purple only
  use selection @DUPE_ANY
    aggregate over selection count
    on result [\$ROLLED:\$ROLLED] action blink purple

  # Non-all-equal → highs and lows
  use selection @ALL_MAX
    aggregate over selection count
    # end-exclusive blocks the all-equal case
    on result [1:\$ROLLED) action blink green

  use selection @ALL_MIN
    aggregate over selection count
    on result [1:\$ROLLED) action blink red
""";

// Variant: blink only one highest (green) and one lowest (red); on tie blink only one purple
const String highLowTiesSingle = """
define highLowTiesSingle for roll *d*
# Blink exactly one die: highest (green) and lowest (red). If all dice tie, blink one die purple and suppress green/red.

  make selection @HIGH
    with top 1

  make selection @LOW
    with bottom 1

  # Tie detection and action (one die): if global MAX equals global MIN, blink the single top die purple
  use selection @HIGH
    aggregate over selection max
    on result [\$MIN:\$MIN] action blink purple
    on result (\$MIN:*) action blink green

  # Only red when not a tie (min strictly less than global max)
  use selection @LOW
    aggregate over selection min
    on result [*:\$MAX) action blink red
""";

// Variant: blink a single highest (green) and a single lowest (red);
// on tie, prefer the max (blink only the single max green; no red/purple)
const String highLowSinglePreferMax = """
define highLowSinglePreferMax for roll *d*
# Blink exactly one highest (green) and one lowest (red). If all dice tie, prefer the max: blink the top die green and do not blink red.

  make selection @HIGH
    with top 1

  make selection @LOW
    with bottom 1

  # Prefer max on tie: when MIN == MAX, only the HIGH branch should fire (green)
  use selection @HIGH
    aggregate over selection max
    # tie case → green on the single top die
    on result [\$MIN:\$MIN] action blink green
    # non-tie case → also green on the top die
    on result (\$MIN:*)   action blink green

  # Only show red when not a tie (i.e., global MIN < global MAX)
  use selection @LOW
    aggregate over selection min
    on result [*:\$MAX) action blink red
""";
