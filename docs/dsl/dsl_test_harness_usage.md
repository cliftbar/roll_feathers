### DSL Test Harness and CLI Runner — Usage

This document explains how to run the local DSL testing tools that were added to the project. They let you provide a DSL rule (inline or from file), specify dice types and face values, and see the actions taken per die.

#### Components
- Library harness: `lib/testing/dsl_test_harness.dart`
  - Provides `DslTestRunner`, `DieInput`, and a `RecordingDieDomain` to capture `blink` actions per die.
- CLI-style runner (via Flutter test): `test/tools/dsl_tester_cli_test.dart`
  - Reads environment variables, runs a rule against supplied dice, and prints lines describing actions and the final result.
- Example unit test: `test/tools/dsl_test_harness_test.dart`
  - Demonstrates using `DslTestRunner` directly from code.

Note: These run under Flutter test because actions depend on Flutter (`material.dart`).

---

### Option A — Run the CLI-style runner

Provide inputs via environment variables and run the single test file. The runner will not assert on outputs; it prints a machine-readable log to stdout.

Environment variables:
- `RULE_TEXT` — Inline rule text (multi-line allowed). If omitted, specify `RULE_FILE`.
- `RULE_FILE` — Path to a text file containing a DSL rule (used when `RULE_TEXT` is empty).
- `DICE` — Comma-separated list of dice specs: `dType:faceValue[#id]`.
  - Examples: `d6:6,d8:3,d6:1` or `d20:15#A1,d20:15#B2` (custom ids after `#`).
- `MODIFIER` — Optional numeric modifier for `$MODIFIER` (default 0).
- `THRESHOLD` — Optional numeric threshold for `$THRESHOLD` (default 0). The CLI runner forwards this into the parser, so rules using `$THRESHOLD` work as-is.

Command examples:

1) All-equal tie on 2×d20 (expect only purple actions)
```
flutter test test/tools/dsl_tester_cli_test.dart \
  --plain-name "DSL tester CLI-style runner" \
  --platform=chrome \
  -d Chrome \
  -- \
  RULE_TEXT='''define highLowAllTiesExclusive for roll *d*

  make selection @ALL_MAX
    with match [$MAX:$MAX]

  make selection @ALL_MIN
    with match [$MIN:$MIN]

  make selection @DUPE_ANY
    with dupes [2:*]

  use selection @DUPE_ANY
    aggregate over selection count
    on result [$ROLLED:$ROLLED] action blink purple

  use selection @ALL_MAX
    aggregate over selection count
    on result [1:$ROLLED) action blink green

  use selection @ALL_MIN
    aggregate over selection count
    on result [1:$ROLLED) action blink red
  ''' \
  DICE='d20:15#A1,d20:15#B2'
```

2) Mixed highs and lows on 3×d6
```
flutter test test/tools/dsl_tester_cli_test.dart \
  -- \
  RULE_TEXT='''define highLow for roll *d*
  make selection @ALL_MAX
    with match [$MAX:$MAX]
  make selection @ALL_MIN
    with match [$MIN:$MIN]
  use selection @ALL_MAX
    aggregate over selection count
    on result [1:*] action blink green
  use selection @ALL_MIN
    aggregate over selection count
    on result [1:*] action blink red
  ''' \
  DICE='d6:6#X,d6:1#Y,d6:6#Z'
```

Output format:
- One line per per-die action: `ACTION <dieId> <action> <colorValueInt?> [args...]`
- Final line with the last aggregate and rule name: `RESULT <ruleName> <aggregateValue>`

---

### Option B — Use the library harness from code

You can embed the harness in your own tests or tooling.

Code snippet:
```
import 'package:roll_feathers/testing/dsl_test_harness.dart';

void main() async {
  final runner = await DslTestRunner.create();
  final res = await runner.run(
    rule: '''define highLow for roll *d*
      make selection @ALL_MAX
        with match [$MAX:$MAX]
      make selection @ALL_MIN
        with match [$MIN:$MIN]
      use selection @ALL_MAX
        aggregate over selection count
        on result [1:*] action blink green
      use selection @ALL_MIN
        aggregate over selection count
        on result [1:*] action blink red
    ''',
    dice: [
      DieInput('d6', 6, id: 'A'),
      DieInput('d6', 6, id: 'B'),
      DieInput('d6', 1, id: 'C'),
    ],
  );

  // res.actions contains one entry per blink with die id and color int.
  for (final a in res.actions) {
    print('ACTION ${a.dieId} ${a.action} ${a.colorValue}');
  }
}
```

---

### Notes and caveats
- The runner currently records `blink`-style actions. `sequence` is implemented internally via repeated `blink` calls and will appear as multiple blink entries.
- v1.1 evaluation reparses rules with `$MAX`, `$MIN`, and `$ROLLED`; ranges support inclusive/exclusive bounds like `[1:$ROLLED)` after substitution.
- If you change the file paths or package name, update the imports accordingly. In normal usage from within this repo, prefer `package:roll_feathers/testing/dsl_test_harness.dart` for the harness import.

---

### Extra examples

3) All dice strictly over a threshold (blink green)
```
flutter test test/tools/dsl_tester_cli_test.dart \
  -- \
  RULE_TEXT=$'define allAboveThreshold for roll *d*\n\n  make selection @ALL_THRESH\n    with match [*:*]\n    with over $THRESHOLD\n\n  use selection @ALL_THRESH\n    aggregate over selection count\n    on result [1:*] action blink green\n' \
  THRESHOLD=4 \
  DICE='d6:5#A,d6:3#B,d6:6#C'
```
Expected: A and C blink green.
