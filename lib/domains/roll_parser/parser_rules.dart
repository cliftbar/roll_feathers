String isSuccessPercentile = """
define is_percentile_success
for roll 1d10,1d00
apply sum
with results
on [0:\$threshold) return true
on [\$threshold:100] return false
""";

String advantage = """
define advantage
for roll 2d20
transform with offset 2 1
apply max
with results
on [0:\$threshold) return true
on [\$threshold:100] return false
""";

String disadvantage = """
define advantage
for roll 2d20
apply min
with results
on [0:\$threshold) return true
on [\$threshold:100] return false
""";

String testRule = """
define sum
for roll 5d20
transform with offset \$modifier with top 3
  with over 10
apply sum
with result
on [*:\$threshold) return true
on [\$threshold:*] return false
""";