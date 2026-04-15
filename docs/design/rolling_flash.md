# Rolling Flash Feature Design

Flash the physical Pixels die's LEDs while it is in a rolling/handling state, stopping cleanly when the die settles so the post-roll rule blink can take over.

## Scope

This is about driving the **physical die's LEDs** over BLE — not the app icon spin animation, which already works independently.

## Design Decisions

### Color

Use the die's existing `dieColor` (currently named `blinkColor`) per-die setting. No separate "rolling color" needed — the same color the result blink uses is appropriate and keeps configuration simple.

### Not part of the rules system

Rolling flash has no roll result to evaluate — it fires before the result is known. It belongs in the die/roll lifecycle, triggered off `DiceRollState.rolling` in `RollDomain` or `DieDomain`, not in the rule parser.

### Blink loop count must be effectively infinite

Roll duration is open-ended. "Shaking in hands" counts as rolling and can last arbitrarily long. A fixed blink count would either:
- Finish too early, leaving the die dark mid-roll
- Require an absurdly large count, then definitely overlap with the result blink

Use max/infinite `loopCount` in `MessageBlink`.

### `stopAllAnimations` is mandatory

Because the rolling blink is infinite, `stopAllAnimations` is the only termination mechanism. It must fire on `DiceRollState.onFace` / stable — before the rule blink plays. This applies even when no rule set is configured.

## Implementation Sequence

1. `DiceRollState.rolling` → `MessageBlink(loopCount: max, blinkColor: die.dieColor, ...)`
2. `DiceRollState.onFace` / stable → `MessageStopAllAnimations()`, then rule blink fires (if rule set present)

## Prerequisite

`stopAllAnimations` is not yet implemented in the app. It is a single-byte TX message — trivial to add to `pixels.dart` and expose through `DieDomain`.

## Animation Ownership Trade-off

`stopAllAnimations` kills firmware-triggered animations too (tagged `AnimationTag_Accelerometer`). If a user has configured custom animations via the official Pixels app, roll_feathers will silence them on every roll settle.

This is an accepted trade-off: **roll_feathers owns the die LEDs when active.** Users who want to run both the official Pixels app profile and roll_feathers simultaneously will see the Pixels profile animations interrupted on each roll.

A future mitigation would be using `fadeOutAnimsWithTag(AnimationTag_BluetoothMessage)` instead of `stopAllAnimations` — this would stop only roll_feathers-sent animations and leave the die's own profile animations running. This requires a firmware message not yet implemented in the app.

## GoDice

`MessageToggleLeds` has no cancel command in the GoDice protocol. Options:
- Tune `numberOfBlinks` + duration to approximate typical roll length (accept slop at end)
- Implement rolling flash for Pixels only initially

## Related Naming Refactor

Rename `blinkColor` → `dieColor` throughout the codebase. Purely mechanical — no logic changes. Files affected:
- `lib/dice_sdks/dice_sdks.dart` — `GenericDie.blinkColor` property
- `lib/ui/die_screen/die_list_tile.dart` — `_blinkColor()` method
- `lib/ui/die_screen/dice_screen.dart` — `_getBlinkColor()` helper
- `lib/ui/die_screen/single_die_settings_dialog.dart` — references for preview flash
