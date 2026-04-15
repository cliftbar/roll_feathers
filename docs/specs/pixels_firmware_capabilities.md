# Pixels Firmware Capabilities

Reference: https://github.com/GameWithPixels/DiceFirmware

## BLE Architecture

Pixels dice are **BLE peripheral only** (`NRF_SDH_BLE_CENTRAL_LINK_COUNT = 0`). No scanning or observer role is implemented. This means:

- Dice cannot receive advertisement packets from devices they are not connected to
- Dice cannot talk directly to each other — all die-to-die coordination must route through the app
- All commands require an active GATT connection; no broadcast/unconnected messaging is possible

## Roll States

The firmware defines six roll states:

| State | Meaning |
|-------|---------|
| `Unknown` | Initial/invalid |
| `OnFace` | Stationary on valid face |
| `Handling` | Being held/manipulated |
| `Rolling` | Active motion |
| `Rolled` | Completed roll on valid face |
| `Crooked` | Landed on invalid face |

The behavior rule system triggers on `Rolling` OR `Handling` for rolling conditions.

## Animation System

- Up to 20 concurrent animations, all **additively blended** — no priority system, no winner
- Two animation source tags:
  - `AnimationTag_Accelerometer` — fired by behavior rules on the die (dataset-driven)
  - `AnimationTag_BluetoothMessage` — sent from the app over BLE
- `fadeOutAnimsWithTag()` can selectively stop one tag group
- `stopAll()` kills all animations regardless of tag and clears LEDs — no roll-state awareness
- No roll-state gating on incoming BLE commands — all messages accepted during rolling

### Animation Sources

| Source | Storage | Persistence |
|--------|---------|------------|
| `transferAnimationSet` | Flash | Permanent, survives reboot |
| `transferInstantAnimationSet` + `playInstantAnimation` | RAM | Cleared on reboot |
| `blink` message | Pool (RAM) | Runs to completion or until `stopAllAnimations` |

Rolling animations are **not hardcoded** in firmware — they are defined in the behavior dataset and may or may not exist depending on die configuration.

### `blink` is an animation

The `blink` message creates an `AnimationSimple` object added to the animation pool like any other animation. It **is** stopped by `stopAllAnimations`.

## `remoteAction` Message

Sent **from the die to the app** when a behavior rule with `Action_RunOnDevice` fires. Contains a 16-bit `actionId`. This is the coordination hook for the app to know when a die-side rule has triggered. Currently ignored by roll_feathers (falls through to default handler).

## What roll_feathers Currently Implements

**TX (app → die):**
- `whoAreYou` ✓
- `blink` ✓

**RX (die → app):**
- `iAmADie` ✓
- `batteryLevel` ✓
- `rollState` ✓
- All others → `MessageNone` default (silently ignored)

## Missing TX Commands

### Trivial (minutes to implement)

| Command | Notes |
|---------|-------|
| `stopAllAnimations` | Single byte. Needed for rolling flash feature. |
| `stopAnimation` | Single byte + animation ID. |
| `requestRollState` | Single byte poll. |
| `sleep` | Single byte. |
| `setName` | Simple string payload. |

### Moderate

| Command | Notes |
|---------|-------|
| `playAnimation` | Simple message, but requires knowing animation IDs from the die's dataset, which varies per die and is not exposed by the app. |

### Complex

| Command | Notes |
|---------|-------|
| `transferInstantAnimationSet` + `playInstantAnimation` | Chunked bulk transfer protocol: `bulkSetup` → `bulkData` chunks → `bulkDataAck` per chunk → `transferInstantAnimationSetFinished`. Requires binary serialization of keyframe/palette animation format. The Pixels JS/TS SDK is the reference implementation to port from. |

## Animation Editor UI Complexity

For a UI to define and upload custom animations to the die:

| Scope | Features | Estimate |
|-------|----------|----------|
| Minimal | Color keyframes, linear interpolation, fixed duration | 4–6 weeks. Still requires custom Flutter timeline widget, binary serialization, bulk transfer protocol. |
| Medium | Easing curves, face mask (per-LED), multiple animations per profile, save/load | 2–3 months |
| Full | Per-LED individual control, real-time preview on die, condition-based profiles | Separate app territory |

The official Pixels app already implements the full scope. For roll_feathers, the narrower goal is likely owning specific animation slots (rolling indicator, result flash) with simple color + duration controls — no full timeline editor needed.
