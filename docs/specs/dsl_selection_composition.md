# DSL Selection Composition — multi-parent `from` and `dtype`

Two new selection primitives that let a rule express a special-case reading of a
roll without any conditional in the language. Motivating case: percentile dice,
where `00` + `0` should read as **100** rather than 0.

## Status

Design only. Neither primitive is implemented. The worked example below does not
parse today.

## Problem

`percentiles` (`for roll 1d10,1d00`) sums the pair. Physical Pixels dice decode
d10 as 0–9 and d00 as 0/10/…/90, so the pair spans **0–99** and a 00+0 roll
reports **0**. By tabletop convention it should be **100**.

Two things are wrong today, not one:

- the recorded value is 0
- 0 falls in the rule's `on result [0:10)` band, so the roll also blinks **red**
  when it should get the top-band treatment

Measured on `main`:

```
d10=0  d00=0   -> reported=0
d10=0  d00=90  -> reported=90
d10=7  d00=40  -> reported=47
```

### Note: virtual and physical dice already disagree

`GenericDTypeFactory` defines virtual `d10` with `indexOffset: 1` (values
**1–10**), while `PixelFaces.faceFromIndex` decodes a physical Pixels d10 as
`index` (values **0–9**). So a virtual percentile pair already spans 1–100 with
no special case, and a physical pair spans 0–99 and needs one. Same rule,
different arithmetic depending on where the dice came from. Out of scope here,
but it should be reconciled — and it is why the fix belongs in the rule system
rather than in `PixelFaces` (0.14.0 deliberately made Pixels d10 report 0–9 to
match the official app).

## Why the existing language cannot express it

The special case is **pair-dependent**: `00` means 100 only when the other die is
also 0. `00` + `5` is 5, not 105. Everything currently available fails on that:

| Mechanism | Why it fails |
|---|---|
| `with offset` / `mul` / `div` | Apply per die, uniformly. `0 × n = 0`; `offset 100` on a pair gives 200. |
| A `d100` die type (`0` → 100) | Per-die, so it cannot see the other die: makes 00+5 into **105**. |
| Post-aggregate remap (`sum == 0 → 100`) | Works for the *total*, but the per-die values stay 0 and 0. See "Per-die fidelity". |
| Selecting the zeros and rescaling | `match [0:0]` + `dupes [2:2]` correctly isolates the pair, but `offset 50` to reach a total of 100 reports **two dice at 50 each** — values that never occurred. |
| Ordering `use` blocks | Since `report` became mandatory it always wins, so block order no longer selects the reported value. |

### Per-die fidelity is the deciding constraint

Selection values flow into `ParseResult.rolledEvaluated`, `blockOutputs`, and
webhook payloads. Any approach that engineers the right *total* by falsifying die
values corrupts that data. The correct reading of a 00+0 roll is **d00 = 100,
d10 = 0** — not two dice at 50, and not two dice at 0 with a patched total.

That rules out both the aggregate remap and the `offset 50` chain, and is the
reason this spec adds selection primitives rather than a scalar tweak.

## Proposed primitives

### 1. Multi-parent `from` — last-wins merge

```
make selection @FINAL
  from @NORM, @HUNDRED
```

A selection is `Map<GenericDie, int>`, so merging parents is a map merge.
**Later parents override earlier ones** on the same die.

This is what removes the need for a conditional: a special-case selection that is
**empty when it does not apply** contributes nothing, and the base parent passes
through untouched. No branch, no set-difference operator.

### 2. `dtype <name>` — filter a selection by die type

```
with dtype d00
```

Keeps only dice whose `dType.name` matches. Needed because the two dice in a
percentile pair are indistinguishable **by value** at exactly the point that
matters — both are the integer `0`.

`RollTransform` is
`Map<GenericDie, int> Function(Map<GenericDie, int>, List<num>)` and the keys are
`GenericDie`, so `dType` is already reachable; no plumbing change is required.
Note the arg is a *name*, not a number — see Open Questions.

## Worked example

```
define percentiles "Percentiles (1d10,1d00)" for roll 1d10,1d00

  make selection @NORM
    from $ALL_DICE

  # Only non-empty on 00+0: both dice show 0, then narrow to the tens die
  # and read it as 100.
  make selection @HUNDRED
    from $ALL_DICE
    with match [0:0]
    with dupes [2:2]
    with dtype d00
    with offset 100

  make selection @FINAL
    from @NORM, @HUNDRED

  use selection @FINAL
    aggregate over selection sum
    on result [1:10)   action blink red
    on result [10:25)  action blink orange
    on result [25:50)  action blink yellow
    on result [50:75)  action blink green
    on result [75:90)  action blink blue
    on result [90:99)  action blink purple
    on result [99:*)   action sequence 1 red orange green blue violet

  report sum over @FINAL
```

| d00 shows | d10 shows | `@HUNDRED` | `@FINAL` dice | reported | band → action |
|---|---|---|---|---|---|
| **00** | **0** | `{d00: 100}` | `{d00: 100, d10: 0}` | **100** | `[99:*)` → sequence |
| 00 | 1 | `{}` | `{d00: 0, d10: 1}` | 1 | `[1:10)` → red |
| 00 | 5 | `{}` | `{d00: 0, d10: 5}` | 5 | `[1:10)` → red |
| 10 | 0 | `{}` | `{d00: 10, d10: 0}` | 10 | `[10:25)` → orange |
| 40 | 7 | `{}` | `{d00: 40, d10: 7}` | 47 | `[25:50)` → yellow |
| 70 | 3 | `{}` | `{d00: 70, d10: 3}` | 73 | `[50:75)` → green |
| 90 | 0 | `{}` | `{d00: 90, d10: 0}` | 90 | `[90:99)` → purple |
| 90 | 9 | `{}` | `{d00: 90, d10: 9}` | 99 | `[99:*)` → sequence |

`@HUNDRED` is empty on every row but the first: `match [0:0]` keeps only dice
showing 0, and `dupes [2:2]` then requires **two** of them. On 00+5 only the d00
shows 0; on 90+0 only the d10 does — multiplicity 1 either way.

The value range becomes a clean **1–100**, every value reachable exactly once, so
the bottom band moves from `[0:10)` to `[1:10)`.

## Implementation

### Grammar (`rule_parser.dart`)

- `_makeSelectionParser`: the `from` clause becomes a comma-separated list of
  selection tokens (currently a single `[_atNameParser, variableParser]` choice).
- `MakeSelectionDef.parent` (`String?`) becomes `parents` (`List<String>`).

### Transforms (`parser_transforms.dart`)

- New `dtype` transform + parser entry, alongside `top`/`bottom`/`match`/`dupes`/….
- Takes a die-type name; filters on `e.key.dType.name`.

### Evaluation (`rule_evaluator.dart`)

- `resolveParent(String?)` becomes a fold over `parents`, merging left to right
  with later entries overriding.
- Empty `parents` keeps today's behaviour (base map).

### Rules (`parser_rules.dart`)

- Update the shipped `percentiles` rule as above, including the band change.
- `d20percentiles` is unaffected (it scales a 2d20 sum by 2.5 and has no zero
  case).

## Sharp edges

These are real and should be documented in the DSL reference, not just here.

**Transform order is load-bearing and fails silently.**
`match → dupes → dtype` works. `match → dtype → dupes` narrows to one die first,
so `dupes [2:2]` never matches and **the rule silently never fires** — no parse
error, no warning, just a percentile roll that reports 0 forever.

**`offset 100` is only correct because of a filter three lines earlier.**
`match [0:0]` pins every value in the selection to 0, which is what makes `+100`
equivalent to "set to 100". Remove or loosen that filter and the offset becomes a
shift.

**Merge precedence is invisible when wrong.** If `from @A, @B` resolved
leftmost-wins instead of last-wins, the percentile rule would report 0 with no
error anywhere.

Together these make the rule correct-as-written but fragile-under-edit. That is
the strongest argument for eventually adding a clearer primitive (a `remap`
transform, or a percentile-aware aggregate) — but neither is needed to ship this.

## Alternatives considered

**Ones die reads 0 as 10** (`d10` variant with `indexOffset: 1`, matching what
virtual dice already do). Costs **zero** new primitives and yields a clean 1–100
bijection with no conditional. Rejected because 100 then comes from **90+0**
rather than 00+0, which changes which physical roll wins. A house-rules decision,
not a technical one — worth revisiting if the convention is negotiable, since it
is by far the cheapest option.

**Post-aggregate remap** (`remap [0:0] to 100` on the report value). Sufficient
for the total — the condition is fully recoverable from the aggregate, since
`sum == 0` happens only for 00+0 — but leaves per-die values at 0 and 0. Rejected
on the fidelity constraint above. Still worth having as a general feature; it just
does not solve this.

**Union + difference + dtype + remap** (four primitives). An earlier sketch used a
set-difference to build the fallback. Last-wins merge makes it unnecessary: the
empty selection is self-gating.

**`with merge @OTHER` as a transform.** Keeps `from` single-parent, but
`RollTransform` args are `List<num>`, so it would need the arg type widened to
carry a selection reference, and it makes one transform structurally unlike every
other. Rejected as a deeper change than it appears.

**A general conditional in the DSL.** Not needed. Every condition here is
expressible as "a selection that is empty when it does not apply."

## Test coverage

- **`dtype`**: filters a mixed pool; unknown type name yields an empty selection;
  interacts correctly with a chained parent.
- **Multi-parent merge**: later wins on collision; disjoint parents union; an
  empty later parent leaves the earlier untouched; single-parent `from` is
  unchanged; three or more parents fold left to right.
- **Percentile rule**: every row of the table above, asserting both the reported
  value **and** the per-die values in `rolledEvaluated` / `blockOutputs`.
- **Regression**: `d20percentiles` and the other shipped rules are byte-identical
  in behaviour.
- **Order sensitivity**: a test pinning that `dtype` before `dupes` produces an
  empty selection, so the sharp edge is at least characterised.

## Open questions

1. **`dtype` argument type.** Transform args are `List<num>` today; a die-type
   name is a string. Either widen the arg type or give `dtype` its own parser
   entry that does not route through `numberParser`.
2. **Unknown type names.** Should `with dtype d7` be a parse error, or silently
   yield an empty selection? A parse error is friendlier but requires the parser
   to know the valid type set.
3. **Merge precedence syntax.** Is `from @A, @B` self-evidently last-wins? An
   explicit form (`from @A override @B`) is uglier but unambiguous.
4. **Does `dtype` want to match the roll-matcher syntax?** `for roll` accepts
   patterns like `*d10`. Reusing that grammar in `dtype` would be consistent but
   is more than this case needs.
