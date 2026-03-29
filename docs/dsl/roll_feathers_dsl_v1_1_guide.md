### Roll Feathers DSL v1.1 — Authoring Guide and Reference

This document explains the Roll Feathers DSL as implemented in the codebase so that you can author any rule. It covers syntax, grammar, semantics, evaluation order, variables, and examples.

#### What this DSL does
- Describes how to react to a dice roll.
- You define selections of dice (filter/transform the rolled dice), aggregate over a selection, and then execute actions based on the aggregated result falling within specified ranges.
- Version 1.1 introduces named selections and explicit “use selection … aggregate … on result … action …” blocks.

---

### Lexical Elements
- Numbers: integers or decimals, e.g., `3`, `2.5`.
- Identifiers: alphanumeric and underscore, e.g., `My_Selection`.
- Variables (special tokens begin with `$`): see Variables section.
- Die notation: `NdM` where `N` is count and `M` is faces. Either side can be `*` (wildcard), e.g., `2d20`, `*d6`, `1d*`, `*d*`.
- Whitespace: flexible around tokens and keywords; newlines separate lines/blocks.
- Comments: A full line starting with optional whitespace then `#` is a comment and is ignored. Inline comments are not supported.

---

### Variables and Special Tokens
At parse or evaluation time, certain variables may be substituted into the script.
- `$MODIFIER`: numeric modifier supplied externally to the parser; available at parse-time substitution.
- `$THRESHOLD`: numeric threshold supplied externally; available at parse-time substitution.
- `$ROLLED_COUNT` and `$ROLLED` (alias): total number of dice in the current roll; substituted at parse-time and again at eval-time safety pass.
- `$MAX`, `$MIN`: the global maximum and minimum face values among all dice in the current roll; these are only known at runtime and are substituted just before evaluation by reparsing the script.
- `$ALL_DICE`: special action argument meaning “target all dice that participated in the roll.”
- `$RESULT_DICE`: legacy token; in v1.1 actions already default to the selection being used. `$RESULT_DICE` is still recognized as an argument token but not needed for v1.1 blocks.

Notes:
- `$MAX` and `$MIN` substitutions happen at evaluation time. The engine reparses the script with these values injected for that single evaluation.
- `$ROLLED`/`$ROLLED_COUNT` are substituted both at initial parse and again at evaluation-time to ensure correctness.

---

### Script Structure (v1.1)
A script has a header, followed by one or more blocks. Blocks are either “make selection …” or “use selection …”. Order matters.

```
define <ruleName> for roll <dieList>
  <block>+
```

- `<ruleName>`: identifier (letters/digits/underscore), e.g., `highLowAllTies`.
- `<dieList>`: one or more die specifiers separated by commas, e.g., `2d20`, `1d10,1d00`, `*d*`.

Blocks (order matters):
- Make block: build a named selection from all dice or another selection.
- Use block: aggregate over a selection and trigger actions for matching result ranges.

---

### Make Selection Blocks
Create or derive a named selection by applying one or more transforms.

```
make selection @<NAME> [from (@<PARENT> | $<VAR>)]
  with <transform>
  with <transform>
  ...
```

- `@<NAME>`: selection name token starts with `@` followed by an identifier (e.g., `@ALL`, `@HIGH`, `@DUPE_ANY`).
- Optional parent: `from @<PARENT>` references an earlier named selection; if omitted, the parent is the implicit base selection consisting of all rolled dice.
- Zero or more `with <transform>` lines are allowed (zero is valid to simply alias the parent selection).

Available transforms (from code in `parser_transforms.dart`):
- `with top N` — keep the top N highest-value dice of the current selection.
- `with bottom N` — keep the bottom N lowest-value dice.
- `with equals N` — keep dice equal to value N.
- `with match N` — keep a “match” group where at least N dice share the same face; among all such groups, keeps the smallest multiplicity bucket (legacy behavior).
- `with match [a:b]` — keep dice whose values are in the interval [a..b]; brackets/parentheses control inclusivity. `*` is allowed as open bound; variables allowed.
- `with dupes [a:b]` — keep all dice that are part of any value-bucket whose multiplicity is within [a..b] inclusive. Example: `dupes [2:*]` keeps all dice that belong to doubles, triples, etc.
- Math transforms on values (integer-rounded after operation): `offset X`, `mul X`, `div X`.
- `over X`, `under X` — value filters strictly greater-than / strictly less-than X.

Transform application semantics:
- Transforms in a `make selection` are applied in order, each operating on the current selection result of the previous step.
- The parent selection (or base roll) is cloned before transforms are applied; parents remain unchanged.

---

### Use Selection Blocks
Aggregate over a selection and perform one or more targets conditioned on the aggregated value.

```
use selection (@<NAME> | $ALL_DICE)
  aggregate over selection <aggregate>
  on result [a:b] <target>
  on result [a:b] <target>
  ...
```

- Selection: either a named selection `@NAME` from a prior make-block or `$ALL_DICE` to use all dice from the original roll.
- Aggregate: one of `sum | min | max | avg | count`.
- One or more `on result [a:b] <target>` entries. The range supports inclusive/exclusive bounds with `[`/`]` vs `(`/`)` and `*` for open-ended.

Tip: You can start from all dice in a make-block explicitly using `from $ALL_DICE`, e.g.,
```
make selection @ALL_MOD
  from $ALL_DICE
  with offset $MODIFIER
  with top 1
```
This applies transforms to the complete set, then trims to a single die.

Aggregates (from `parser_aggregates.dart`):
- `sum` — sum of values.
- `min` — minimum value.
- `max` — maximum value.
- `avg` — average (rounded to nearest int).
- `count` — number of dice in the selection.

---

### Result Ranges
`on result [a:b]` uses interval semantics:
- Bounds may be written with inclusive `[]` or exclusive `()` sides, e.g., `[10:25)`.
- `*` can be used for open bounds: `[*:10]`, `[10:*]`, `[*:*]`.
- Numeric bounds may be decimal; they are rounded to integers. After accounting for inclusivity, the effective integer interval is used for comparison.

Important: Arithmetic inside bounds (e.g., `$ROLLED-1`) is not supported. Prefer inclusive/exclusive endpoints to model inequalities, e.g., use `[1:$ROLLED)` instead of `[1:$ROLLED-1]`.

---

### Targets (Actions and Rules)
A target is one of:
- Action: `action <name> [args…]`
- Rule: `rule <name> [args…]` (disabled in v1.1; parsed in legacy but ignored in v1.1 evaluation path)

Built-in actions (from `result_targets.dart`):
- `blink [<color>] [($ALL_DICE)]` — blink the target dice (or all dice if `$ALL_DICE` arg supplied) in the specified color. If no color given, the die’s configured color or white is used.
- `sequence <loops> <color1> <color2> ... [($ALL_DICE)]` — blink a sequence of colors for each target die, repeated `loops` times (default loops = 1).

Action dice targeting in v1.1:
- By default, the action’s “result dice” are the dice in the current use-block’s selection.
- If you include `$ALL_DICE` in the action arguments, that additionally targets all rolled dice as the “allDice” set (in addition to the selection as resultDice). The `$ALL_DICE` token itself is removed from the args passed to the action implementation.
- `$RESULT_DICE` is accepted as a token in args but is unnecessary in v1.1 since the selection is already used as the result set by default.

Transforms vs. use-blocks:
- Transforms (`with …`) are only allowed in make-blocks. You cannot apply transforms inside a `use selection` block. Build any modified selection you need first, then use it.

Colors:
- Named colors are defined in `colorMap` (see `lib/util/color.dart`). Only known color names are accepted as a single arg token (the parser restricts arg tokens to variables, color names, and numbers so keyword boundaries are not consumed by free text).

---

### Roll Pattern Matching (Header `for roll …`)
The header specifies which dice patterns a rule applies to. Pattern matching expands each `NdM` entry into a list and checks the incoming roll’s type sequence against it.

- Each entry in `<dieList>` is a die spec:
  - `*d*` — matches anything and clears any remaining required pattern (wildcard consumes all).
  - `*dM` — matches any die of faces `M`; consumes the next die in the incoming sequence.
  - `Nd*` — matches any die type (faces), exactly `N` times, consuming `N` dice.
  - `NdM` — matches a specific type, `N` times (order-insensitive across the whole pattern, except for `Nd*` which consumes in sequence). The engine removes matched items as it finds a type; if a required specific type cannot be found, the rule does not apply.
- After expanding, the pattern “passes” only if all expected items are accounted for and no extra unmatched dice remain. If it fails, no blocks execute.

Notes:

---

### Evaluation Order (v1.1)
1. Parse the script and substitute `$MODIFIER`, `$THRESHOLD`, `$ROLLED`/`$ROLLED_COUNT` (initial pass).
2. When evaluating a specific roll:
   - Build a base map from all rolled dice to their face values.
   - Compute `$MAX` and `$MIN` from the base map; re-substitute `$ROLLED` and reparse the script with those concrete values for this evaluation.
   - Build named selections in order of appearance:
     - Determine the parent selection (explicit `from` or the base map).
     - Apply each `with …` transform in order to produce the selection.
   - For each `use selection` block in order:
     - Resolve the referenced selection (or `$ALL_DICE`).
     - Compute the aggregate value over that selection’s values.
     - For each `on result [a:b] …` whose range contains the aggregate value, fire the action target.
3. Actions do not short-circuit other actions or blocks. Each `use` block is independent.
4. In v1.1, rule-return booleans are not used; the overall `ParseResult.ruleReturn` is always `true` if the pattern matched (and blocks executed), otherwise actions do not run.

---

### Grammar (EBNF-like)
This is an approximate grammar reflecting the actual parsers in code.

```
script         := header block+ ;
header         := 'define' IDENT 'for roll' dieSpecList ;
dieSpecList    := dieSpec (',' dieSpec)* ;
dieSpec        := (NUMBER|'*') 'd' (NUMBER|'*') ;

block          := makeBlock | useBlock ;

makeBlock      := 'make selection' ATNAME [ 'from' (ATNAME | VARIABLE) ] transformDef* ;
transformDef   := 'with' transform ;
transform      :=
    'top' NUMBER
  | 'bottom' NUMBER
  | 'equals' NUMBER
  | 'match' NUMBER
  | 'match' valueInterval
  | 'dupes' valueInterval
  | 'offset' NUMBER
  | 'mul' NUMBER
  | 'div' NUMBER
  | 'over' NUMBER
  | 'under' NUMBER
  ;

valueInterval  := ( '[' | '(' ) ( NUMBER | '*' | VARIABLE ) ':' ( NUMBER | '*' | VARIABLE ) ( ']' | ')' ) ;

useBlock       := 'use selection' (ATNAME | VARIABLE /*$ALL_DICE*/)
                  'aggregate over selection' aggregate
                  resultLine+ ;

aggregate      := 'sum' | 'min' | 'max' | 'avg' | 'count' ;

resultLine     := 'on' 'result' resultInterval target ;
resultInterval := ( '[' | '(' ) ( NUMBER | '*' ) ':' ( NUMBER | '*' ) ( ']' | ')' ) ;

target         := actionTarget | ruleTarget ;
actionTarget   := 'action' IDENT arg* ;
ruleTarget     := 'rule'   IDENT arg* ;  // disabled in v1.1 evaluation

arg            := VARIABLE | COLORNAME | NUMBER ;

ATNAME         := '@' IDENT ;
VARIABLE       := '$' IDENT ;
IDENT          := [A-Za-z0-9_]+ ;
NUMBER         := digit+ ('.' digit+)? ;
COLORNAME      := one of keys in colorMap ;
```

Notes:
- The `over` and `under` transforms exist in code but, like other transforms, only affect selection content/values; they are not validations of the final aggregate unless you structure selections accordingly.
- The arg token set is deliberately limited to variables, color names, and numbers to avoid greedy consumption into the next keyword.

---

### Examples

1) Standard sum with modifier and color by any result
```
define standardRoll for roll *d*

  make selection @ALL
    with match [*:*]
    with offset $MODIFIER

  use selection @ALL
    aggregate over selection sum
    on result [*:*] action blink green
```

2) Advantage on 2d20 (blink highest die green)
```
define advantage for roll 2d20

  make selection @TOP
    with top 1

  use selection @TOP
    aggregate over selection max
    on result [*:*] action blink green
```

3) Highlight any duplicates among any number of dice
```
define highLowAllEqual for roll *d*

  make selection @DUPE_ANY
    with dupes [2:*]

  use selection @DUPE_ANY
    aggregate over selection count
    on result [$ROLLED:*] action blink purple
```

4) Percentiles built from 1d10 and 1d00
```
define percentiles for roll 1d10,1d00

  make selection @ALL
    with match [*:*]
    with offset $MODIFIER

  use selection @ALL
    aggregate over selection sum
    on result [90:99) action blink purple
  use selection @ALL
    aggregate over selection sum
    on result [99:*)  action sequence 2 red orange yellow green blue indigo violet
```

5) All highs and all lows (using global min/max)
```
define highLowAllTies for roll *d*

  # All dice equal to the global maximum
  make selection @ALL_MAX
    with match [$MAX:$MAX]

  # All dice equal to the global minimum
  make selection @ALL_MIN
    with match [$MIN:$MIN]

  use selection @ALL_MAX
    aggregate over selection count
    on result [1:*] action blink green

  use selection @ALL_MIN
    aggregate over selection count
    on result [1:*] action blink red
```

---

### Authoring Checklist
- Header
  - Choose a rule name and declare `for roll` pattern using `NdM` with optional `*` wildcards.
- Build selections
  - Use `make selection @NAME [from @PARENT]`.
  - Chain `with …` transforms in order; prefer interval forms for range/multiplicity logic.
- Use selections
  - For each `use selection`, choose an `aggregate` and define one or more `on result [a:b] action …` lines.
  - Arguments are limited to variables, numbers, and known color names.
  - Default action target is the selection’s dice; add `$ALL_DICE` in args if you also want to reference all rolled dice inside the action.
- Variables
  - `$MODIFIER`, `$THRESHOLD` are provided by the caller; `$ROLLED`/`$ROLLED_COUNT` derive from the current roll.
  - `$MAX`, `$MIN` become concrete at evaluation time; the engine reparses with those injected.
- Comments
  - Use `#` at the start of a line to comment out that line.

---

### Differences vs. Legacy
- v1.1 replaces earlier single-block scripts with structured make/use blocks and removes rule-return based flow control (rules in targets are ignored at runtime).
- Actions in v1.1 default to the selection’s dice rather than requiring `$RESULT_DICE`.

---

### Troubleshooting and Common Errors
- “Rule doesn’t trigger”: verify the `for roll` pattern matches the incoming dice types and counts; remember that `*d*` swallows all remaining requirements.
- “Action didn’t fire”: ensure the aggregate value falls within at least one `on result` interval; check inclusivity `[]` vs `()`.
- “Transforms seem to do nothing”: confirm the correct parent selection is used; if omitted, parent is the base roll result. Also ensure earlier transforms didn’t filter everything out.
- “Color not applied”: verify the color name exists in `colorMap`.
