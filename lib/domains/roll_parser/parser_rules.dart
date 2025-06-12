String percentiles = """
define percentiles
for roll 2d20
transform with mul 2.5
apply sum
with result
on [0:10) action blink \$ALL_DICE red
on [10:25) action blink \$ALL_DICE orange
on [25:50) action blink \$ALL_DICE yellow
on [50:75) action blink \$ALL_DICE green
on [75:90) action blink \$ALL_DICE blue
on [90:*) action blink \$ALL_DICE purple
""";

String advantage = """
define advantage
for roll 2d20
transform with top 1
apply max
""";

String disadvantage = """
define disadvantage
for roll 2d20
transform with bottom 1
apply min
""";

String standardRoll = """
define standardRoll
for roll *d*
transform with offset \$MODIFIER
apply sum
with result
on [*:*] action blink \$ALL_DICE
""";

String minRoll = """
define minRoll
for roll *d*
transform with offset \$MODIFIER
  with bottom 1
apply min
with result
on [*:*] action blink \$RESULT_DICE red
""";

String maxRoll = """
define maxRoll
for roll *d*
transform with offset \$MODIFIER
  with top 1
apply max
with result
on [*:*] action blink \$RESULT_DICE
""";

String simpleTest = """
define sum
for roll 2d20
transform with offset \$MODIFIER
apply sum
with result
on [*:\$THRESHOLD) rule return true
on [\$THRESHOLD:*] rule return false
on [\$THRESHOLD:*] action blink \$RESULT_DICE green
""";