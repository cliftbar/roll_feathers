### Rule: highLowAllTiesExclusive — Highlight highs, lows, and exclusive all-tie

Purpose
- Runs on any roll pattern (`for roll *d*`).
- Highlights all dice equal to the global maximum value in green.
- Highlights all dice equal to the global minimum value in red.
- If and only if all dice show the same value (an all-tie), highlights all dice in purple, and suppresses red/green via exclusive ranges.

How it works (DSL v1.1)
- Build selections:
  - `@ALL_MAX`: all dice whose value equals `$MAX` at evaluation time (`with match [$MAX:$MAX]`).
  - `@ALL_MIN`: all dice whose value equals `$MIN` at evaluation time (`with match [$MIN:$MIN]`).
  - `@DUPE_ANY`: all dice that belong to any face bucket whose multiplicity is ≥ 2 (`with dupes [2:*]`). When all dice are the same face, this selection equals the full set of rolled dice.
- Use-blocks and exclusivity:
  - First, aggregate `count` over `@DUPE_ANY`. If the count equals `$ROLLED` exactly, all dice are duplicates of the same value → blink purple.
  - Then, aggregate `count` over `@ALL_MAX` and `@ALL_MIN`. Each fires only when the count is in `[1:$ROLLED)` — the end-exclusive interval avoids the all-equal case (where the count would be `$ROLLED`).

Why exclusivity is needed
- In an all-tie, both `@ALL_MAX` and `@ALL_MIN` contain all dice. Without exclusive bounds, green and red would also fire. The `[1:$ROLLED)` ranges ensure only purple triggers for ties.

Complete rule text
```
define highLowAllTiesExclusive for roll *d*

  make selection @ALL_MAX
    with match [$MAX:$MAX]

  make selection @ALL_MIN
    with match [$MIN:$MIN]

  make selection @DUPE_ANY
    with dupes [2:*]

  # All-equal → purple only
  use selection @DUPE_ANY
    aggregate over selection count
    on result [$ROLLED:$ROLLED] action blink purple

  # Non-all-equal → highs and lows
  use selection @ALL_MAX
    aggregate over selection count
    on result [1:$ROLLED) action blink green

  use selection @ALL_MIN
    aggregate over selection count
    on result [1:$ROLLED) action blink red
```

Notes
- `$MAX`, `$MIN`, and `$ROLLED` are substituted per evaluation (the engine reparses with concrete values), enabling the interval bounds above.
- The rule fires on any number and type of dice due to the `*d*` header pattern.
