# Roll Feathers DSL — Proposed Additions

This document outlines two proposed additions to the DSL action semantics. These are forward-looking specs meant to guide parser/runtime changes and authoring guidance.

Version: Draft-2026-03-26

## 1) Palette Cycling (Per-Die Color Cycling)

Goal: Allow actions to apply a sequence of colors across the targeted dice in order, cycling if there are more dice than colors.

### Authoring Syntax (proposed)

Option A — extend `blink` action with a `palette` keyword:

```
use selection @RESULT
  aggregate over selection sum
  on result [*:*] action blink palette red yellow green
```

Option B — introduce a new action `palette`:

```
use selection @RESULT
  aggregate over selection sum
  on result [*:*] action palette red yellow green
```

Recommendation: Option B (new action) keeps `blink` semantics simple and avoids argument overloading.

### Semantics

- Input: ordered list of colors C = [c0, c1, ..., c_{k-1}].
- Target dice: the action’s `resultDice` in iteration-stable order (engine-defined, e.g., stable by insertion or deterministic ID sort).
- For the i-th die in `resultDice`, apply `blink` with color `C[i mod k]`.
- If `$ALL_DICE` is present as an argument, pass it through to the action for potential context, but color assignment uses only `resultDice` index.

### Runtime/Parser Changes

- Parser: register new `palette` action that accepts 1..N color tokens and optional `$ALL_DICE`.
- Runtime: implement `ActionPalette` to iterate `resultDice` and call `die.blink(color)` with cycled color.
- Validation: require at least 1 color, ensure all tokens are valid color names.

### Examples

```
define cycleExample for roll *d*

  make selection @ALL
    with match [*:*]

  use selection @ALL
    aggregate over selection count
    on result [1:*] action palette red yellow green
```

Behavior: First die blinks red, second yellow, third green, fourth red, etc.

## 2) Gradient Mapping (Value-Based Color Interpolation)

Goal: Map a numeric value to a color by interpolating between two endpoint colors, enabling heatmap-like feedback.

### Authoring Syntax (proposed)

Option A — new action `gradient` with endpoints and optional domain:

```
use selection @ALL
  aggregate over selection sum
  on result [*:*] action gradient blue red domain [$MIN:$MAX]
```

Option B — extend `blink` with `gradient <colorA> <colorB> domain [a:b]`:

```
on result [*:*] action blink gradient blue red domain [0:100]
```

Recommendation: Option A (new action) for clarity and easier parsing.

### Semantics

- Inputs:
  - Two endpoint colors A (at t=0) and B (at t=1).
  - Domain interval [L:R] that defines the mapping of a numeric driver value to t in [0,1]. If omitted, default domain is the aggregate’s min/max theoretical range or `[0:$MAX]` depending on aggregate; see below.
- For each target die, compute driver `v` as either:
  - The aggregate value of the `use selection` block (default), or
  - Optionally, the per-die value (advanced variant: `per-die` flag). This variant requires explicit design and is out of scope for first iteration.
- Normalize: `t = clamp((v - L) / (R - L), 0, 1)`; if `L == R`, treat `t = 1` if `v >= R` else 0.
- Interpolate per ARGB channel: `color = lerp(A, B, t)` using linear interpolation in sRGB; integer rounding to nearest.
- Apply `blink(color)` to each die in `resultDice`.

### Domain Defaults

- If `aggregate == sum` or `avg`: default domain `[0 : $ROLLED * $MAX]` (or for `avg`, `[0 : $MAX]`).
- If `aggregate == min`: default domain `[$MIN : $MAX]`.
- If `aggregate == max`: default domain `[$MIN : $MAX]`.
- If `aggregate == count`: default domain `[0 : $ROLLED]`.

Authors can override with `domain [a:b]`, which accepts numbers or variables (e.g., `$MIN`, `$MAX`, `$ROLLED`).

### Parser/Runtime Changes

- Parser: add `gradient` as an action accepting: `<colorA> <colorB> [ 'domain' interval ] [($ALL_DICE)]`.
- Interval parsing can reuse existing result-interval parser but must allow variables.
- Runtime: implement `ActionGradient` that resolves domain bounds at eval-time (after `$MIN/$MAX/$ROLLED` substitution) and computes color via interpolation.
- Validation: ensure two valid colors; if domain present, ensure `a != *` and `b != *` (open bounds are not allowed for interpolation).

### Examples

Aggregate-driven gradient over sum with explicit domain:
```
define gradientExample for roll *d*

  make selection @ALL
    with match [*:*]

  use selection @ALL
    aggregate over selection sum
    on result [*:*] action gradient blue red domain [0:100]
```

Min/max-driven gradient without explicit domain:
```
define gradientMinMax for roll *d*

  make selection @ALL
    with match [*:*]

  use selection @ALL
    aggregate over selection max
    on result [*:*] action gradient green yellow
```

## Open Questions / Future Extensions

- Ordering of `resultDice`: define deterministic order (e.g., by die id) to stabilize palette cycling.
- Per-die gradient driver: add optional `per-die` flag to use each die’s value instead of aggregate.
- Easing: support non-linear ramps (`ease-in`, `ease-out`) via optional keyword.
- Color spaces: consider linear RGB vs sRGB for interpolation; start with sRGB for simplicity.
- Chaining: should `palette`/`gradient` combine with existing `sequence`? For now, treat them as separate actions.

## Backward Compatibility

- New actions do not affect existing scripts. Parsers that don’t recognize them should fail validation clearly.
