String d20percentiles = """
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

String percentiles = """
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

String doubles = """
define doubles
for roll *d*
transform with match 2
aggregate sum
with result
on [*:*) action blink \$RESULT_DICE blue
""";

String advantage = """
define advantage
for roll 2d20
transform with top 1
aggregate max
""";

String disadvantage = """
define disadvantage
for roll 2d20
transform with bottom 1
aggregate min
""";

String standardRoll = """
define standardRoll
for roll *d*
transform with offset \$MODIFIER
aggregate sum
with result
on [*:*] action blink \$ALL_DICE
""";

String minRoll = """
define minRoll
for roll *d*
transform with offset \$MODIFIER
  with bottom 1
aggregate min
with result
on [*:*] action blink \$RESULT_DICE red
""";

String maxRoll = """
define maxRoll
for roll *d*
transform with offset \$MODIFIER
  with top 1
aggregate max
with result
on [*:*] action blink \$RESULT_DICE green
""";

String simpleTest = """
define sum
for roll 2d20
transform with offset \$MODIFIER
aggregate sum
with result
on [*:\$THRESHOLD) rule return true
on [\$THRESHOLD:*] rule return false
on [\$THRESHOLD:*] action blink \$RESULT_DICE green
""";
