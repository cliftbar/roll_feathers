import 'dart:convert';

import 'package:roll_feathers/domains/roll_parser/parser_definitions.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';

final List<RuleScript> defaultRules = [
  RuleScript(name: 'd20percentiles', script: d20percentiles, enabled: false),
  RuleScript(name: 'percentiles', script: percentiles, enabled: false),
  RuleScript(name: 'doubles', script: doubles, enabled: false),
  RuleScript(name: 'nDupes', script: nDupes, enabled: false),
  RuleScript(name: 'advantage', script: advantage, enabled: false),
  RuleScript(name: 'disadvantage', script: disadvantage, enabled: false),
  RuleScript(name: 'standardRoll', script: standardRoll, enabled: true),
  RuleScript(name: 'webhookExample', script: webhookExample, enabled: false),
  RuleScript(name: 'maxWithModifier', script: maxWithModifier, enabled: false),
  RuleScript(name: 'allAboveThreshold', script: allAboveThreshold, enabled: false),
  RuleScript(name: 'averagePassFailD10', script: averagePassFailD10, enabled: false),
  RuleScript(name: 'highLowAllTiesExclusive', script: highLowAllTies, enabled: false),
  RuleScript(name: 'highLowTiesSingle', script: highLowTiesSingle, enabled: false),
  RuleScript(name: 'highLowSinglePreferMax', script: highLowSinglePreferMax, enabled: false),
];

class RuleScript {
  final String name;   // ruleId: define block identifier, unique key
  final String script;
  bool enabled;
  int? priority;
  RuleScript({required this.name, required this.script, required this.enabled, this.priority = intMaxValue});

  // Derived from the optional "Display Name" in the define line; falls back to name.
  late final String displayName = parseDisplayName(script) ?? name;

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
    return RuleScript(
      name: data["name"] as String,
      script: data["script"] as String,
      enabled: data["enabled"] as bool,
      // JS JSON.parse returns double for all numbers; cast via num to handle both
      priority: (data["priority"] as num?)?.toInt(),
    );
  }
}

const String d20percentiles = """
define d20percentiles "Percentiles (2d20)" for roll 2d20

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
define percentiles "Percentiles (1d10,1d100)" for roll 1d10,1d00

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
define doubles "Doubles" for roll *d*

  make selection @DUPE2
    with dupes [2:2]

  use selection @DUPE2
    aggregate over selection count
    on result [1:*] action blink blue
""";

const String nDupes = """
define nDupes "Duplicates" for roll *d*

  make selection @NDUPE
    with dupes [\$THRESHOLD:\$THRESHOLD]

  use selection @NDUPE
    aggregate over selection count
    on result [1:*] action blink blue
""";

const String advantage = """
define advantage "Advantage" for roll 2d20

  make selection @TOP
    with top 1

  use selection @TOP
    aggregate over selection max
    on result [*:*] action blink green
""";

const String disadvantage = """
define disadvantage "Disadvantage" for roll 2d20

  make selection @BOT
    with bottom 1

  use selection @BOT
    aggregate over selection min
    on result [*:*] action blink red
""";

const String standardRoll = """
define standardRoll "Basic Blink" for roll *d*

  use selection \$ALL_DICE
    aggregate over selection sum
    on result [*:*] action blink
""";

const String webhookExample = """
define webhookExample "Webhook Example" for roll *d*

  make selection @TOP
    with top 1

  use selection @TOP
    aggregate over selection max
    on result [*:*] action blink green
    on result [*:*] webhook POST http://localhost:8765/hook
    on result [*:*] discord https://discord.com/api/webhooks/your_webhook_id/your_webhook_token
""";

const String maxWithModifier = """
define maxWithModifier "Max (with Modifier)" for roll *d*
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
define allAboveThreshold "All Above Threshold" for roll *d*

  make selection @ALL_THRESH
    with match [*:*]
    with over \$THRESHOLD

  use selection @ALL_THRESH
    aggregate over selection count
    on result [1:*] action blink green
""";

const String averagePassFailD10 = """
define averagePassFailD10 "Avg Pass/Fail (d10)" for roll *d10

  make selection @ALL
    with match [*:*]

  use selection @ALL
    aggregate over selection avg
    on result [*:5] action blink red
    on result (5:10] action blink blue
""";

const String highLowAllTies = """
define highLowAllTiesExclusive "High/Low/Tie All" for roll *d*
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
define highLowTiesSingle "High/Low/Tie Single" for roll *d*
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
define highLowSinglePreferMax "High/Low" for roll *d*
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
