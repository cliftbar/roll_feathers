# DSL Webhook Targets

## Overview

Adds `webhook` as a first-class target type in the rules DSL, alongside the existing `action`
type. When a result range matches, a webhook fires an HTTP request to a configurable URL with
a JSON payload describing the roll context.

## DSL Syntax

```
# POST (default) — sends full JSON payload as request body
on result [*:*] webhook https://my.server.com/roll-hook

# GET — appends aggregate and rule name as query params, no body
on result [10:20] webhook GET https://my.server.com/hook
```

- Only `GET` and `POST` are supported.
- If the first token after `webhook` is `GET` or `POST` (case-insensitive), it is consumed as
  the method. Otherwise `POST` is assumed and the entire rest-of-line is the URL.

## Example Rule

```
define Webhook Test for roll *d*

  make selection @ALL

  use selection @ALL
    aggregate over selection sum
    on result [*:*] action blink blue
    on result [*:*] webhook POST https://webhook.site/your-uuid
```

Multiple targets in the same `on result` block are all fired; blink and webhook can coexist.

---

## POST Payload

```json
{
  "rule":          "Webhook Test",
  "timestamp":     "2026-04-04T12:34:56.789Z",
  "aggregate":     7,
  "matched_range": {
    "start": -9000000000000000,
    "end":    9000000000000000,
    "start_inclusive": true,
    "end_inclusive":   true
  },
  "result_dice": [
    { "id": "abc123", "name": "Red Pixel",  "type": "d6", "value": 4, "battery": 85 },
    { "id": "def456", "name": "Blue Pixel", "type": "d6", "value": 3, "battery": 90 }
  ],
  "all_dice": [
    { "id": "abc123", "name": "Red Pixel",  "type": "d6", "value": 4, "battery": 85 },
    { "id": "def456", "name": "Blue Pixel", "type": "d6", "value": 3, "battery": 90 }
  ],
  "actions": [
    { "type": "blink", "args": ["blue"] }
  ]
}
```

### Field Reference

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `rule` | string | `result.name` | Name of the rule that fired |
| `timestamp` | ISO 8601 string | `DateTime.now().toUtc()` | Captured at fire time |
| `aggregate` | int | `aggValue` from the `use selection` block | The computed value that matched the range |
| `matched_range` | object | `res.resultRange` | Raw stored bounds + inclusive flags |
| `matched_range.start` | int | `RollResultRange.start` | Pre-inclusive-adjustment bound |
| `matched_range.end` | int | `RollResultRange.end` | Pre-inclusive-adjustment bound |
| `matched_range.start_inclusive` | bool | `RollResultRange.startInclusive` | |
| `matched_range.end_inclusive` | bool | `RollResultRange.endInclusive` | |
| `result_dice` | array | `selMap.keys` | Dice selected by this block's `make selection` chain |
| `all_dice` | array | `rolls` | All dice passed into the evaluator |
| `battery` | int | `die.state.batteryLevel` | **Omitted** from die object if null |
| `actions` | array | Pre-scan of `block.targets` | Other `action`-type targets in the same `use selection` block whose range also matches `aggValue`. Webhook entries excluded. `$ALL_DICE`/`$RESULT_DICE` tokens stripped from args. |

### Die Object Fields

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `die.dieId` — unique hardware identifier |
| `name` | string | `die.friendlyName` — human-readable name |
| `type` | string | `die.dType.name` — "d4", "d6", "d8", "d10", "d12", "d20", "d00", "unknown" |
| `value` | int | Face value (`selMap[die]` for result_dice, `getFaceValueOrElse()` for all_dice) |
| `battery` | int? | Battery percent 0–100; key omitted if unavailable |

---

## GET Request

No request body. Two query parameters are appended to the URL (merged with any params already
present via `Uri.replace(queryParameters: {...})`):

| Param | Value |
|-------|-------|
| `aggregate` | String form of `aggValue` |
| `rule` | Rule name |

Example: `GET https://my.server.com/hook?aggregate=7&rule=Webhook+Test`

---

## Error Handling

Errors (network failure, bad URL, non-2xx response) are caught and logged at `WARNING` level
via the existing `_rtLog` logger. A failed webhook never throws or interrupts dice behavior.

---

## Schema / Storage Impact

None. `RuleScript.script` is stored as a verbatim string via `jsonEncode` in SharedPreferences.
URLs serialize without issue. No changes to `RuleScript`, storage, or serialization.

The DSL grammar parser must recognize the `webhook` keyword — this is required for `addRuleScript()`
to succeed, since it runs `_parseRule()` to extract the rule name on save.

---

## Implementation

### `lib/domains/roll_parser/result_targets.dart`
- Add imports: `dart:convert`, `package:http/http.dart` as `http`
- Add `webhookP` parser inside the `resultTarget` IIFE (after `actionSequenceP`, before `actionP`)
  - Captures rest-of-line; splits optional method prefix (`GET`/`POST`)
  - Stores URL in `ResultTargetFunction.action`, method in `args[0]`
- Add `fireWebhook({url, method, payload})` function after `sequence`

### `lib/domains/roll_parser/parser.dart`
- Three `case ResultTargetType.webhook: break;` stubs to fill:
  - **Async path** `_evaluateRuleV11Async` (~line 709): full payload, `await fireWebhook(...)`
    - Pre-scan `coActions` (other matching action targets in the same block) before the target loop
  - **Sync v1.0 path** `_evaluateRule` (~line 424): minimal payload, fire-and-forget (`.ignore()`)
  - **Sync v1.1 path** `_evaluateRuleV11` (~line 588): minimal payload, fire-and-forget (`.ignore()`)

### No changes needed
- `parser_rules.dart` — `RuleScript` schema unchanged
- `app_service.dart` — verbatim string storage
- `script_screen.dart` — UI unchanged; webhook rules authored like any other rule
- `pubspec.yaml` — `http` is already a dependency
