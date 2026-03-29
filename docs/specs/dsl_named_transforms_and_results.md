# DSL v1.1: Per‑block selections, explicit aggregates, and interval match (TDD-first)

This document is the single source of truth for the new rule DSL design. It captures the background, alternatives explored, rationale, the finalized syntax and semantics, a TDD-first verification plan, and future notes (syntactic sugar, performance, and upcoming operators).

## Background and current behavior
- Existing parser (see `lib/domains/roll_parser/`) parses one rule into: roll pattern, a single transform pipeline, one aggregate, and a single result block with `on [range]` actions that execute immediately against the die domain.
- `$RESULT_DICE` and `$ALL_DICE` markers are allowed in action args; actions are async but currently not awaited in sequence; some arg lists are mutated during evaluation.
- Multi-rule orchestration and multiple result blocks per rule are limited, making combined visual semantics harder.
### Research
#### Fit matrix: how the DSL compares to common dice systems

| System | Expressiveness | Player readability | Parser complexity | Runtime complexity | Fit |
|---|---:|---:|---:|---:|---|
| D&D-style d20 | Medium | High | Low | Low | Good |
| Year Zero Engine | High | High | Medium | Medium | Excellent |
| World of Darkness / Chronicles of Darkness | High | High | Medium | Medium | Excellent |
| Genesys / FFG narrative dice | High | Medium | High | High | Partial |
| Tracker / gauge / threshold systems | High | High | Medium | Medium | Excellent |

#### Notes by system

- **D&D-style d20**
  - Strong fit for single-roll threshold checks.
  - Easy to author and explain.
  - Your DSL is more expressive than needed here, but still workable.

- **Year Zero Engine**
  - One of the best matches.
  - Success counting, pool filtering, and threshold bands map cleanly to named selections and explicit aggregates.
  - Good validation target for the first implementation pass.

- **World of Darkness / Chronicles of Darkness**
  - Also a strong fit.
  - Success counting and high-face rules fit the selection model well.
  - Advanced reroll / “again” behavior is a good candidate for future operators.

- **Genesys / FFG narrative dice**
  - Only a partial fit.
  - The core mechanic is symbol cancellation across multiple axes, which is not the same thing as numeric selection.
  - The DSL can model some outcome presentation, but not the native probability structure very naturally.

- **Tracker / gauge / threshold systems**
  - Excellent fit.
  - These systems often need “if total is in this band, do this” behavior, which matches explicit aggregates and range-gated actions well.

#### Recommendation

This DSL should be treated as a strong fit for **numeric dice systems**:
- threshold checks
- success pools
- keep-highest / keep-lowest
- result bands
- tracker-style triggers

It should **not** be expected to cover Genesys-style symbol cancellation without a larger rule-model extension.

#### Scope guidance

- **Ship first for numeric systems**
  - d20
  - Year Zero–style success pools
  - World of Darkness–style success pools
  - percentile bands
  - tracker thresholds

- **Defer symbol-based narrative dice**
  - treat as a separate future model, not just another syntax tweak

## Problem statement and goals
- Need a DSL that selects combinations of rolled dice to light up across varied game use cases (TTRPGs, board games, trackers).
- Priorities: 1) Flexibility, 2) Simplicity (local reasoning, minimal hidden state), 3) Lower verbosity where possible.

## Alternatives considered (summary)
- Sequential multi-rule orchestration with priorities (simple, but implicit conflicts).
- Intent collection + channels/layers per die (structured, but larger refactor).
- DSL composition with named selections and multiple result blocks (chosen path): enables rich, per-block control with explicit semantics and good readability.

## Final DSL (Option A) — Overview
- Keep block header as: `with selection <SELECTION>` for readability.
- In selection pipelines, use `with <op> <args>` for each step (reads naturally: “make selection @NAME with top 1 with offset 10”).
- Move aggregation into each block explicitly: `aggregate over selection <sum|min|max|avg>`.
- Gate actions with per-block ranges: `on result [<range>] action <action-name> <args...>`.
- Remove `$RESULT_DICE` as a concept/alias in v1.1; selections are either named (`@NAME`) or `$ALL_DICE` (convenience global retained).

Note: We evaluated and accepted the design refinement that effect blocks should not include transform steps. All selection logic must be defined in named pipelines via `make selection` (optionally derived `from` another). Effect blocks use a named selection and only specify how to evaluate and act.

## Grammar
```
define <RULE_NAME>
for roll <ROLL_PATTERN>

// Reusable named pipelines (definitions only)
make selection @NAME                 // defines a reusable selection pipeline
  with <op> <args>                   // 1..N steps (filters/value ops)
  with <op> <args>

// Deriving new selections from existing ones
make selection @CHILD from @PARENT   // start from an existing named selection
  with <op> <args>

// One or more effect blocks
use selection @NAME                        // application: no transforms allowed here
  aggregate over selection <sum|min|max|avg>
  on result [<range>] action <action-name> <args...>
  on result [<range>] rule   <rule-name>   <args...>
```

Note on formatting vs syntax
- Newlines and indentation in the examples are for readability only. The DSL should be parsed based on keywords and token order, not line breaks. For example, the following single-line form is equivalent to the multi-line form:
```
make selection @HIGHEST with top 1
use selection @HIGHEST aggregate over selection max on result [*:*] action blink green
```
- Authors are encouraged to format rules over multiple lines for clarity, but the grammar must not depend on newlines.

Transform operators (order matters):
- Selection/ranking (affect membership; values pass through):
  - `top N`, `bottom N`, `over N`, `under N`, `equals N` (compat), `match [start:end]`, `dupes [min:max]`
  - Interval brackets: `[`/`]` inclusive, `(`/`)` exclusive; `*` allowed for unbounded, e.g., `[10:*]`, `(*:5]`, `[3:3]`.
  - `dupes [min:max]`: same‑face multiplicity filter. Builds a histogram of current selection by face value and keeps all dice whose face occurs between `min..max` times (inclusive). Examples: `[2:*]` = at least doubles; `[2:2]` = pairs only; `[3:3]` = exactly triples.
- Value-changing (affect values for downstream steps and aggregate):
  - `offset N`, `mul N`, `div N`.

Per-block semantics:
- Start map `M0` comes from a named selection only: `use selection @NAME` resolves to that named pipeline’s final map. No transforms are permitted inside a `use selection` block.
- To refine or build composed selections, define them with `make selection @CHILD from @PARENT` and additional `with` steps.
- Aggregation is explicit and required whenever ranged `on result` is used.
- Actions run on the resolved selection’s keys; evaluator awaits actions within a block for deterministic visuals; parsed args remain immutable.

## Runtime / evaluation model
1) Snapshot base roll map `{die -> faceValue}`.
2) Evaluate all named pipelines defined via `make selection` (including any `from @PARENT` chains).
3) For each `use selection` block in source order:
   - Resolve the named selection’s final map (or `$ALL_DICE`).
   - Compute `rollResult_block = aggregate(values(selection))`.
   - For each `on result [range]` that matches, execute its actions against the selection’s dice in order, awaiting within the block.

## Verification plan (TDD-first)
Step 1: Create tests and sample rules before parser changes.
- Parser tests for:
  - `make selection @NAME` header and nested `with <op> <args>` steps.
  - `use selection <SELECTION>` blocks with per-block `aggregate` and `on result [range]`.
  - `match [a:b]` intervals, inclusive/exclusive, and `*` bounds.
  - `dupes [a:b]` same‑face multiplicity with `*` bounds.
  - Aggregates: `sum|min|max|avg`.
- Evaluator tests for:
  - Correct selection membership and values through pipelines.
  - Deterministic action execution order; actions awaited per block.
  - Immutability of action args during evaluation.
- Sample rules (used as fixtures and doc examples):
  1) D20 check (success/fail via ranges and named pipelines).
  2) Advantage/disadvantage (highest/lowest of 2d20).
  3) Extremes (highlight highest/lowest) and conditional sequence on high max.
  4) Percentile classification (bands via `match [a:b]`).
  5) Doubles/matches (via `dupes [a:b]`).
  6) Tracker-style rule (e.g., gating by `sum` or `avg`).

Step 2: Implement parser/runtime to satisfy tests (after tests are green for parsing expectations).

## Examples
1) Extremes + conditional sequence
```
define extremes
for roll *d*

make selection @HIGHEST
  with top 1

make selection @LOWEST
  with bottom 1

use selection @HIGHEST
  aggregate over selection max
  on result [*:*] action blink green

use selection @LOWEST
  aggregate over selection min
  on result [*:*] action blink red

make selection @HIGH_BAND from @HIGHEST
  with match [15:*]

use selection @HIGH_BAND
  aggregate over selection max
  on result [18:*] action sequence red blue green
```

2) Success/fail via ranges
```
define d20_check
for roll 1d20

make selection @SUCCESS
  with match [10:*]

make selection @FAIL
  with match [*:9]

use selection @SUCCESS
  aggregate over selection sum
  on result [*:*] action blink blue

use selection @FAIL
  aggregate over selection sum
  on result [*:*] action blink orange
```

3) Value transforms affect gating when local to block
```
define scaledTop
for roll *d*

make selection @SCALED_TOP
  with mul 2
  with top 1

use selection @SCALED_TOP
  aggregate over selection max
  on result [*:*] action blink purple
```

## Player Guide (templates you can copy/paste)
- Highest/lowest emphasis
```
make selection @HIGHEST with top 1
make selection @LOWEST with bottom 1
use selection @HIGHEST aggregate over selection max on result [*:*] action blink green
use selection @LOWEST  aggregate over selection min on result [*:*] action blink red
```

- Simple check (d20 success ≥ 10)
```
make selection @SUCCESS with match [10:*]
use selection @SUCCESS aggregate over selection sum on result [*:*] action blink blue
```

- Bands (percentile vibes)
```
make selection @BAND1 with match [* : 9]
make selection @BAND2 with match [10:24]
make selection @BAND3 with match [25:49]
use selection @BAND1 aggregate over selection max on result [*:*] action blink red
use selection @BAND2 aggregate over selection max on result [*:*] action blink orange
use selection @BAND3 aggregate over selection max on result [*:*] action blink yellow
```

- Scaled top (multiply then pick highest)
```
make selection @SCALED_TOP with mul 2 with top 1
use selection @SCALED_TOP aggregate over selection max on result [*:*] action blink purple
```

## Future operators (documented, not implemented in v1.1)
- `count` (aggregate): number of dice in the current selection. Useful for success-count mechanics (e.g., count how many dice ≥ threshold). Syntax (proposed): `aggregate over selection count`.
- `explode on [a:b]` (transform): when a die’s value falls in the interval, generate an additional contribution (e.g., add another roll or add a fixed value). Requires clear semantics about recursion/limits to avoid infinite expansion and to define fairness. Not implemented yet.
- `reroll under N` (transform): if a die’s value is below a threshold, replace it with a (conceptual) new value. Needs policy on maximum rerolls and whether rerolled values can trigger other transforms. Not implemented yet.

## Syntactic sugar (postponed)
- Documented ideas (not implemented now):
  - `with selection using @NAME` as alias for `with selection @NAME`.
  - Range shorthands: `any` → `[ * : * ]`, `ge N`, `gt N`, `le N`, `lt N`.
  - One-liner blocks: `with selection @HIGHEST aggregate over selection max do [*:*] action blink green`.
  - These reduce boilerplate but are deferred for clarity and to keep parser scope focused.

## Player-first authoring guidance (non-programmers)
This DSL is intended for players, not programmers. To keep it approachable:
- Plain verbs: “make selection” and “use selection” describe exactly what you do.
- Named recipes: Use friendly names like `@HIGHEST`, `@SUCCESS`, `@ONES`. Think of “make selection” as saving a filter you can reuse, and “use selection” as choosing which saved set to light up.
- Minimal math: Aggregates are simple choices (sum, highest, lowest, average). If you use a range, read it as “from … to …”. Examples in this doc cover common game patterns to copy and tweak.
- No code in action blocks: Effects don’t change which dice are included; they only say “when the total is in this band, do this light effect.” That keeps rules consistent and easy to read aloud.
- Editor UX (future): The rule editor should show chips like [top 1], [over 10], [x2], and preview what `@NAME` means when you hover, so you don’t need to open definitions while authoring.

Example in words
- “Make selection HIGHEST: pick the highest die.”
- “Use selection HIGHEST: if its value is anything, blink green.”
This mirrors: `make selection @HIGHEST → transform top 1` and `use selection @HIGHEST → aggregate max → on result any blink green`.

## Implementation notes
- Parsing:
  - Support `transform @NAME` headers with nested `transform <op> <args>`.
  - Support `with selection <SELECTION>` blocks, per-block `aggregate over selection <fn>`, and `on result [range]`.
  - Add interval `match [a:b]` with inclusive/exclusive brackets and `*` bounds.
  - Remove support and examples for `$RESULT_DICE` and `transform with ...` in v1.1 (no deprecation window needed per guidance).
- Evaluation:
  - Snapshot base once; compute named pipelines; execute blocks in order; apply local transforms; compute aggregate; evaluate ranges; run actions.
  - Keep args immutable; await actions within a block by default for deterministic visuals.
- Performance note:
  - Future optimization: cache intermediate pipeline results per (base, pipeline signature) within a single rule evaluation to avoid recomputation across blocks. See also docs/specs/dsl_selection_pipeline_caching.md (design is documented but currently deferred).

## Next steps (do not start implementation yet)
1) Selection sources (final): keep `$ALL_DICE` as a global convenience source in `use selection` for players; also allow named selections. Additional useful globals to reserve for future: `$ODDS`, `$EVENS`, `$CRITICALS` (domain-preserved for editor/UI macros; not implemented in v1.1).
2) Derivation shape (final): `make selection @CHILD from @PARENT` accepts exactly one parent (simple chains). Set operations (union/intersection/difference) are deferred.
3) Per-step operator (final): use `with <op> <args>` inside `make selection` pipelines (e.g., `make selection @HIGHEST with top 1`).
4) Interval match (final): `match [start:end]` supports inclusive/exclusive brackets and `*` for unbounded; no additional sugar (like `in 1,2,3`) in v1.1.
5) Aggregates (final): allowed functions are `sum|min|max|avg`. `count` is documented for future but not implemented now.
6) Future operators scope (final): `count` (aggregate), `explode on [a:b]` (transform), and `reroll under N` (transform) remain documented only in v1.1.
7) Syntactic sugar (final): all sugars (e.g., `using @NAME`, range shorthands, one-liners) are documented but not implemented now.
8) Formatting rule (final): newlines/indentation are not part of the grammar; parsing is token/keyword-based.
9) TDD scaffolding (final):
   - Tests under `test/domains/roll_parser/` using `package:test`.
   - Prefer rule fixtures in `test/fixtures/` so examples can be reused in docs.
   - Initial sample set: d20 check (success/fail), advantage/disadvantage, extremes, percentile bands, doubles/matches, tracker-style threshold.
10) Player guide (final): include a “Player Guide” section with copy/paste templates for common patterns.


## research references

- RPG dice systems overview and tradeoffs  
  [[1]](https://screenrant.com/tabletop-rpg-dice-systems-rules-mechanics-good-bad/)

- Dice pool success counting and threshold-based resolution  
  [[2]](https://harpscorp.com/how-do-dice-rolls-work-ttrpg/)

- Generic RPG / board-game rule parser discussion  
  [[3]](https://softwareengineering.stackexchange.com/questions/170867/generic-rule-parser-for-rpg-board-game-rules-how-to-do-it)

- Year Zero Engine SRD  
  [[4]](https://freeleaguepublishing.com/wp-content/uploads/2023/11/YZE-Standard-Reference-Document.pdf)

- Year Zero Engine success counting discussion  
  [[5]](https://rpg.stackexchange.com/questions/210201/count-successes-in-pools-of-stepped-dice)

- Year Zero probability analysis  
  [[6]](https://www.frank-mitchell.com/posts/yet-more-year-zero-again/)

- World of Darkness rules overview  
  [[7]](https://epicsavingthrow.com/world-of-darkness-rules/)

- WoD / Chronicles of Darkness “again” mechanics discussion  
  [[8]](https://rpg.stackexchange.com/questions/166844/rote-action-and-10-9-8-again-in-nwod)

- Genesys narrative dice overview  
  [[9]](https://philgamer.wordpress.com/2018/07/25/lets-study-genesys-part-1-narrative-dice-basic-rules/)

- Genesys symbols summary  
  [[10]](https://wiki.roll20.net/Genesys)


Checkpoint 2026-03-22 (development snapshot)

- Current focus: DSL v1.1 only (legacy routing removed). Legacy tests are skipped. Rule returns removed in v1.1 (cooperative blocks only).
- Parser status:
  - Mixed-block parsing by keywords (make selection / use selection) supports inline or multi-line formatting.
  - Interval match [a:b] accepts internal whitespace and * bounds with inclusive/exclusive brackets.
  - make selection @CHILD from @PARENT accepts @NAME or $ALL_DICE and allows zero steps.
  - use selection <@NAME | $ALL_DICE> with per-block aggregate and on result [range] targets.
- Evaluator status:
  - Builds all named selections once, then evaluates each use-block independently (selection -> aggregate -> gate -> actions). Args are immutable; actions invoked in block order.
  - No temporary debug prints remain; evaluator logs are clean.
- Tests:
  - Parsing fixtures under test/fixtures/ and flutter_test-based parser test in place.
  - Evaluation tests cover: extremes (highest/lowest), interval bands (low/mid/high), $ALL_DICE convenience, derived chains (from @PARENT), multiple use-blocks sharing one selection, cross-block independence (different aggregates over same selection), and in-block action order determinism.
  - Suite is green (with some legacy tests intentionally skipped by design).
- Known risks/weaknesses observed during iteration:
  - Block boundary sensitivity was addressed by moving to mixed-block parsing; continue to validate with inline scripts.
  - Ensure all use selection blocks execute (no unintended short-circuit). Range gating must be recomputed per block.
  - Remove legacy coupling completely to avoid confusion during v1.1 rollout.
- Next concrete steps:
  1) Periodically re-run the evaluation suite to guard against regressions across extremes (both highest and lowest), bands (LOW/MID/HIGH), $ALL_DICE, and shared-range scenarios.
  2) —
  3) Add one assertion for arg immutability and (optionally) one for in-block action ordering.
  4) Consider caching selection pipeline results per evaluation for performance (future optimization).
  5) Document a short migration guide (legacy -> v1.1) and add Player Guide templates to README or in-app help.
  6) Decide whether to fully remove legacy parser/evaluator or expose them behind an explicit alternative entry point.