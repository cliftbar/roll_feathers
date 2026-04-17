# Webhook Refactor Session — Design Doc

> Branch: `cb_webhookTargets`
> Builds on: `docs/specs/webhook_dto_di_discord_design.md` (initial webhook DTO/DI/Discord spec)

---

## What This Session Did

This session completed and cleaned up the webhook feature after the initial implementation. Changes span DI wiring, DTO consolidation, evaluator refactoring, interface design, dead code removal, and platform hygiene. The overall theme was **reducing accidental complexity** — removing duplication, giving things accurate names, and cutting code that was no longer load-bearing.

---

## 1. DTO Consolidation into `target_dtos.dart`

### What changed
`RollResultPayload`, `DiscordRollPayload`, and `WebhookDieInfo` were scattered across `result_targets.dart` and `discord_roll_payload.dart`. They were consolidated into a single new file, `lib/domains/roll_parser/target_dtos.dart`, and renamed with the `DTO` suffix:

| Old name | New name |
|---|---|
| `RollResultPayload` | `RollResultDTO` |
| `DiscordRollPayload` | `DiscordRollDTO` |
| `WebhookDieInfo` | `DieInfoDTO` |
| *(inline `Map<String, dynamic>`)* | `ActionDTO` |

`ActionDTO` is new — it replaced the raw `List<Map<String, dynamic>>` used for co-actions, giving the co-action list type safety and a `toJson()` implementation in one place.

`DiscordRollDTO` gained a `fromRollData()` static factory to match `RollResultDTO`, so both full-payload DTOs have a consistent construction API.

### Why DTO not Payload
"Payload" implied the object was already ready to send. "DTO" is the broader term — these objects carry structured data and may be serialized in multiple ways. The naming also matches the codebase convention used elsewhere.

### Naming norm
Dart convention doesn't mandate a suffix for data classes. The `DTO` suffix was chosen deliberately over no suffix because the objects are pure data carriers with no domain logic, and grouping them by suffix makes their role immediately clear when reading imports.

---

## 2. `JsonSerializable` and `WebhookPayload` Interface Split

### What changed
`WebhookSerializable` (two methods: `toJson()` + `toQueryParams()`) was split into:

- `JsonSerializable` (`toJson()` only) — lives in `lib/util/json_serializable.dart`
- `WebhookPayload extends JsonSerializable` (`toQueryParams()` added) — lives in `lib/domains/webhook_domain.dart`

All four DTOs implement `JsonSerializable`. Only `RollResultDTO` and `DiscordRollDTO` implement `WebhookPayload`, since they are the only ones sent directly as HTTP payloads.

`fireWebhook()` takes `WebhookPayload`.

### Why split
`DieInfoDTO` and `ActionDTO` have `toJson()` but are not standalone HTTP payloads — they are nested sub-objects. Forcing them to implement `toQueryParams()` would have been a meaningless stub. The split respects that distinction.

### Why `util/` for `JsonSerializable`
`JsonSerializable` is a generic serialization contract with no dependency on the webhook domain or the parser. Placing it in `util/` makes it reusable across the codebase without pulling in HTTP or domain concerns. Since everything is in the same `roll_feathers` package, no export re-forwarding was needed — importers reference `util/json_serializable.dart` directly.

---

## 3. RuleParser Lifted into DI

### What changed
`RuleParser` was previously constructed inside `RollDomain._()`, making it invisible to `DiWrapper` and creating a circular dependency (`RollDomain` → `RuleParser` → `RollDomain`). It was lifted to a top-level DI citizen:

- `RuleParser` is now constructed and initialized in `initDi()` before `RollDomain`
- `RollDomain.create()` takes `ruleParser:` as a required named parameter
- `DiWrapper` exposes `ruleParser` as a public field
- All UI access changed from `_diWrapper.rollDomain.ruleParser.X` to `_diWrapper.ruleParser.X`

### Why it broke the circular dependency
The circular dependency existed because `ResultTarget` functions previously received a `RollDomain` parameter (`rd`). That parameter was never actually used by any handler. Removing it was the root fix; lifting `RuleParser` to DI was the structural consequence.

### Codebase norm match
Other domains (`DieDomain`, `WebhookDomain`, `ApiDomain`) are all top-level DI citizens. `RuleParser` now matches that pattern.

---

## 4. `WebhookDomain` Removed from `RollDomain`

### What changed
`RollDomain` had a `final WebhookDomain webhookDomain` public field that was stored but never read internally. It was removed. `WebhookDomain` remains in `DiWrapper` directly.

### Why
Storing an object just to hold a reference is an anti-pattern. `RollDomain`'s job is rule evaluation; `WebhookDomain` is `RuleParser`'s concern. Removing it sharpened the responsibility boundary.

---

## 5. Evaluator Refactor — Shared Helpers

### What changed
`_evaluateRuleV11` (sync) and `_evaluateRuleV11Async` (async) had ~150 lines of duplicated setup code each. Five shared private helpers were extracted:

| Helper | Purpose |
|---|---|
| `_prepareEvaluation()` | Roll pattern check, baseMap construction, `$MAX/$MIN/$ROLLED` substitution + re-parse, named selection building |
| `_resolveSelection()` | Resolves a block's selection token to a `Map<GenericDie, int>` |
| `_buildCoActions()` | Pre-scans action-type targets in a block that match `aggValue`; builds `List<ActionDTO>` |
| `_buildActionCallArgs()` | Resolves the `ResultTarget` fn, dice lists, and filtered args for an action dispatch |
| `_buildParseResult()` | Constructs the final `ParseResult` |

`_buildCoActions()` was a side-fix: the sync path had never included co-actions in the webhook payload (bug). Extracting the helper fixed both paths identically.

### Named classes instead of anonymous records
The helpers initially returned Dart 3 anonymous record types (e.g. `({bool passed, Map<GenericDie, int> baseMap, ...})`). These were replaced with named private classes `_PreparedEval` and `_ActionCallArgs`.

**Why**: Anonymous records inline into the method signature, producing a long opaque type declaration above the method name. Named classes are more readable, show up correctly in stack traces and hover docs, and follow standard Dart practice. The anonymous record syntax is useful for quick one-off returns but not for types that are passed between multiple helpers.

---

## 6. Sync Evaluation Path Removed

### What changed
`runRule` (sync) and the private `_evaluateRuleV11` (sync) were deleted. `runRuleAsync` was renamed to `runRule`; `_evaluateRuleV11Async` was renamed to `_evaluateRuleV11`. All call sites updated. The commented-out `switch` block in `roll_domain.dart` (which referenced `runRule`) was also deleted.

### Why
Two reasons, both apply:

1. **No live callers.** The only call sites were in a commented-out `switch` block — dead code from a migration that had already completed. The codebase had fully moved to async evaluation.

2. **Async-first is the right model.** Actions (`blink`, `sequence`) operate hardware and need to be awaited for deterministic sequencing. Webhooks need to be awaited so error handling is predictable. A sync fire-and-forget path was always the wrong model for these side effects — it existed as a transitional step, not a target design.

### Codebase norm
Flutter/Dart conventionally uses `async/await` throughout. The sync path was the outlier.

---

## 7. User-Agent Header and App Version in DI

### What changed
`WebhookDomain.fireWebhook()` now sends `User-Agent: roll-feathers/<version>` on all outbound requests (both GET and POST). The version string is:

- Read once in `initDi()` via `PackageInfo.fromPlatform()`
- Stored on `DiWrapper.appVersion`
- Passed to `WebhookDomain(appVersion: ...)` at construction
- Also passed to `DiceScreenWidget` via `create(di)`, replacing the widget's own `_loadVersion()` call and `PackageInfo` import

### Why DI, not per-request
`PackageInfo.fromPlatform()` is async and non-trivial. Reading it once at startup and distributing the string is cleaner than every call site re-reading it. It also makes `DiceScreenWidget` simpler — the version is guaranteed available at build time rather than loading asynchronously after init.

### Why User-Agent
Standard HTTP practice. Receiver logs (Discord, custom servers, Home Assistant) can identify the source and version. Also enables server-side version gating if the payload schema ever changes.

---

## 8. Platform Considerations

### Android
`INTERNET` permission already present in `AndroidManifest.xml`. No changes needed.

### macOS
`com.apple.security.network.client` already in both `DebugProfile.entitlements` and `Release.entitlements`. No changes needed.

### iOS — NSAllowsArbitraryLoads (pending)
iOS App Transport Security (ATS) blocks plain HTTP by default. Webhook URLs are user-configured and may point to `http://` endpoints (e.g. a local Home Assistant instance). ATS blocks these silently — the `try/catch` in `fireWebhook` catches and logs the error, but the user gets no feedback.

**Decision: add `NSAllowsArbitraryLoads: true` to `Info.plist`.**

Rationale: roll_feathers sends controlled, structured payloads to user-defined destinations (which may be the user's own server). It takes no action on the response body. This is the same rationale Apple accepts for apps like Shortcuts and webhook integrations. The key distinction Apple looks for is that the user is choosing the endpoint, not the app developer.

*This change has not been made yet — it is documented here as the decided approach.*

### Web
No permissions needed. Browsers allow outbound requests freely. The constraint is CORS on the receiving server. Since the app fires webhooks and ignores responses, a missing CORS header has no practical effect.

### Linux / Windows
No manifest or permission required. Outbound TCP is unrestricted.

---

## 9. `ResultTargetFunction.action` Renamed to `target`

### What changed
The `action` field on `ResultTargetFunction` was renamed to `target`.

### Why
The field held different things for different types:
- For `action` type: an action name (`"blink"`) — the word "action" fit
- For `webhook` type: a URL — not an action
- For `discord` type: a URL — not an action

`target` is accurate for all cases: it is the destination of dispatch regardless of type.

---

## 10. Dispatch Architecture — Why Webhooks Are Not in `resultAction`

### The question
One proposal was to register webhook dispatch in the `resultAction` map (alongside `blink` and `sequence`) to unify how all result targets work.

### Why it was rejected
The `resultAction` map stores `ResultTarget` functions:

```dart
typedef ResultTarget = Future<void> Function({
  required DieDomain dd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  required List<GenericDie> defaultDice,
  List<String> args,
});
```

This signature was designed for die-manipulation actions. It provides `DieDomain` and dice lists. Webhooks need the opposite: the aggregate value, matched range, rule name, co-actions, and `WebhookDomain` — none of which are in the signature.

Putting webhooks in the map would require either:
- Expanding `ResultTarget` to carry all evaluation context, making it heavier and mixing HTTP concerns into a die-manipulation typedef
- Building closures at parse time that still can't close over runtime values like `aggValue` and `coActions`

**The switch on `ResultTargetType` is the correct dispatch mechanism.** Dart's exhaustive switch ensures every case is handled at compile time — a map lookup cannot provide that. The map exists specifically because action names are user-visible DSL tokens added by name at parse time; webhook URLs are runtime data, not registered names.

**Final position: settled. `resultAction` stays die-manipulation only.**

---

## 11. `rule` Target Type Removed

### What changed
`ResultTargetType.rule`, the `ruleP` parser block, `ResultRule` typedef, `ret()` function, `resultRules` map, and the `case ResultTargetType.rule: continue` switch arm were all deleted.

### History
The `rule return true/false` DSL target was a mechanism to explicitly set `ruleReturn` on `ParseResult` from within a result block. It allowed a script to signal evaluation success/failure rather than relying on the computed `passed` flag. In v1.1, with structured multi-block evaluation, this was no longer needed — `passed` is determined entirely by whether the dice matched the roll pattern.

The map was emptied with the comment `"v1.1: drop support for rule returns to simplify cooperative blocks"` but the surrounding scaffold (enum case, parser guard, switch arm) was left in place. This session removed the scaffold.

**Decision: permanently removed.** There are no plans to revive a rule-return mechanism. If evaluation control between blocks becomes necessary in the future, it would be a new design — not a revival of this one.

---

## Key Files After This Session

| File | Role |
|---|---|
| `lib/util/json_serializable.dart` | `JsonSerializable` interface |
| `lib/domains/webhook_domain.dart` | `WebhookPayload` interface, `WebhookDomain.fireWebhook()` |
| `lib/domains/roll_parser/target_dtos.dart` | `DieInfoDTO`, `ActionDTO`, `RollResultDTO`, `DiscordRollDTO` |
| `lib/domains/roll_parser/result_targets.dart` | DSL parsers, `ResultTargetType` enum (3 cases), `ResultTargetFunction`, `blink`, `sequence`, `resultActionMap` |
| `lib/domains/roll_parser/parser.dart` | `RuleParser`, evaluation helpers, `_evaluateRuleV11` |
| `lib/di/di.dart` | Top-level DI: `WebhookDomain`, `RuleParser`, `appVersion` |
