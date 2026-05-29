# Changelog

## 0.12.19

### Internal

- **Ignore worktrees** — Added `.worktree/` to `.gitignore`.
- **Split `RuleParser` out of `RuleEvaluator`** — DSL parsing (data classes, constants, static petitparser combinators, and `parse()`) now lives in a dedicated `RuleParser` class with static-only access. `RuleEvaluator` retains rule management and roll evaluation. No behaviour change; all 260 tests pass.

## 0.12.18

### Bug Fixes

- **Roll history silently lost on mobile Chrome** — Virtual dice rolls were never recorded to roll history on mobile Chrome (desktop and iOS Safari unaffected). `_stopRollWithResult` ran fire-and-forget inside a `Timer`, and rule evaluation fired side effects (blink / webhook / Discord) inline. The blink path always read Home Assistant config via `SharedPreferencesAsync` (IndexedDB on web), which can throw on mobile Chrome (stricter storage policy, private mode, aggressive eviction). That exception propagated through the un-awaited call and prevented the roll from ever being inserted into history. The fix separates evaluation, recording, and side effects so a side-effect failure can no longer destroy the roll record on any platform.

### Internal

- **Rule evaluation / recording / side-effect separation** — `runRule` and `_evaluateRuleV11` no longer fire blink/webhook/Discord actions inline; they collect them as deferred closures on a new `RuleEvaluation { result, effects }` return type. `_stopRollWithResult` now runs in three explicit phases: pure evaluation → guaranteed history recording (no I/O in front of it) → best-effort side effects, fired fire-and-forget with errors logged via `_log.warning`. `runRule` is now synchronous (previously `Future<ParseResult>`) since evaluation no longer performs I/O.
- **Home Assistant blink early-exit** — `blinkEntity` now returns immediately when HA is unavailable and not forced, skipping four `SharedPreferencesAsync` reads on every roll even when HA is disabled or all dice are virtual.
- **Virtual roll Timer awaits result** — the `rollAllVirtualDice` Timer callback now `await`s `_stopRollWithResult` rather than discarding it.
- **Empty-roll bounds guard** — `_makeRollText` no longer unconditionally indexes `rollsWithColors[0]`, which could throw `RangeError` when there were no colored rolls.
- **DSL test harness** — updated for the new `RuleEvaluation` return type; it now explicitly runs the deferred effects (`runEffects()`) before mapping blink actions, since effects are no longer fired during `runRule`.

## 0.12.17

### Features

- **Webhook example rule** — New built-in `webhookExample` rule (hidden by default) demonstrates all three action targets firing together — blink, webhook POST, and Discord embed — on any roll. Serves as a copy-paste starting point for webhook and Discord rules.
- **Rule display names** — Rules can now declare a quoted display name on the `define` line (e.g. `define myRule "My Rule" for roll *d*`). The display name is derived from the script itself at parse time; nothing extra is stored in JSON. All built-in default rules now embed their display names this way. User rules without a quoted name fall back to showing the identifier. Old saved JSON with a `displayName` key is silently ignored (backwards compatible).
- **Dash support in rule IDs** — Rule identifiers now allow hyphens in non-leading positions (`my-rule`, `advantage-v2`). The first character must still be alphanumeric or underscore.

### Bug Fixes

- **Auto-roll switch alignment** — The auto-roll toggle on the main dice screen was vertically misaligned with the Add Die / Pair Die / Roll buttons. Fixed by adding `WrapCrossAlignment.center` to the header row and removing excess vertical padding from the switch card.
- **User rule indicator** — Changed the user-defined rule indicator icon from ⭐ to 👤 to better distinguish user rules from default rules.

## 0.12.16

### Bug Fixes

- **Rule persistence (fire-and-forget)** — All four rule management operations (add, toggle, reorder, remove) were discarding their async futures, so `notifyListeners` could fire before the write to `SharedPreferences` completed. Each operation now `await`s persistence before notifying listeners.
- **Invalid DSL silently accepted** — Parse errors on rule save were swallowed. Errors now propagate to the VM, which sets a `saveError` state; the add/edit dialog stays open and shows the error message inline rather than saving a broken rule.
- **Remove default rule was a no-op** — Removing a built-in default rule had no effect. Default rules are now hidden rather than deleted (stored under a `hidden_rule_names` key). A "N hidden rules" section appears at the bottom of the list with individual Restore buttons.
- **Reorder only applied to user rules** — Drag-to-reorder operated on the user rules list only, making it impossible to interleave user and default rules. Ordering is now driven by an explicit `rule_order` list (stored under a `rule_order` key) that spans both user and default rules.
- **No rollback on persistence failure** — If a write to `SharedPreferences` failed, the in-memory state was already mutated with no way to recover. All four mutation methods now snapshot state before mutating and restore the snapshot on failure.
- **New default rules invisible to returning users** — Default rules added in a new app version would not appear for users who already had a saved rule order. `init()` now appends any default rule entries absent from the saved order, so new built-in rules surface automatically on upgrade.
- **Snackbar spam on save error** — A save error snackbar could re-fire on every unrelated `notifyListeners()` call while `saveError` was set. A `_lastShownError` guard now prevents duplicate snackbars.

### Features

- **New rules inserted at top of list** — Newly added user rules appear at the top of the rules list rather than the bottom.
- **User rule indicator** — User-defined rules now display a star icon (amber) to distinguish them from built-in default rules.

### Internal

- **Test infrastructure** — Added `NoopBleRepository`, `NoopHaService`, `DiWrapper.forTesting()`, and an extended `InMemoryAppService` to support rule VM and widget tests without a full DI graph. Added 44 new tests across the rule evaluator, settings screen VM, and script screen widget layers.

## 0.12.15

### Features

- **Webhook targets** — DSL rules now support `on result [range] webhook [GET|POST] <url>`. On match, fires an HTTP request to the configured URL. POST sends a structured JSON payload (`RollResultDTO`) with rule name, timestamp, aggregate value, matched range, result dice, all dice, and co-actions. GET appends `aggregate` and `rule` as query parameters. Errors are caught and logged; dice behavior is never interrupted. A `webhooks_enabled` app setting gates all outbound webhook and Discord requests.
- **Discord targets** — DSL rules support `on result [range] discord <webhook_url>`. Fires a Discord embed (`DiscordRollDTO`) with roll metadata, matched range, and dice values formatted as embed fields.
- **`RuleEvaluator`** — The rule evaluation engine (previously `RuleParser`) has been renamed, refactored, and lifted into top-level DI as a singleton. The legacy v1.0 synchronous evaluation path and all dead rule target types have been removed. `WebhookDomain` and `RuleEvaluator` are now injected where needed rather than constructed inline.
- **`webhook_listener.py`** — Added a development utility script (`scripts/webhook_listener.py`) for testing webhook targets locally.

### Bug Fixes

- **Rule persistence (missing await)** — `setSavedScripts` was missing `await` on its `setStringList` call, causing saves to complete out of order under load.
- **Rule VM silently discarded async errors** — Rule management VM methods were not propagating async errors, masking persistence failures.
- **JSON type coercion on web** — `fromJsonString` field casts have been hardened to handle JS integer/double type coercion differences that caused deserialization failures on web.

### Internal

- **Import normalization** — All `lib/` source files converted from relative imports to `package:roll_feathers/` style for consistency.
- **Test coverage** — 48 new tests covering DSL parsing, evaluation, HTTP dispatch (GET/POST), Discord payloads, and integration scenarios.

## 0.12.14

### Internal

- **Release tooling** — `deploy.sh` now bumps the pubspec version before tagging, ensuring the git tag always matches the Gradle archive name. Also fixed tagging to use `HEAD` instead of `origin/main` to avoid ambiguity with a stray tag of the same name. Versions 0.12.12 and 0.12.13 were skipped due to these tagging issues.

## 0.12.11

### Bug Fixes

- **Tests** — Fixed a compilation error caused by `FakeDie` not implementing the `friendlyName=` setter added to `GenericDie` in 0.12.10.

## 0.12.10

### Features

- **Adaptive layout** — The main dice screen responds to screen size. Narrow/tall screens stack the dice list and roll history vertically; wide screens place them side by side. An extremely small window collapses into a single scrollable list.
- **Layout orientation setting** — New "Layout Orientation" option in app settings lets you pin the layout to Horizontal, Vertical, or Auto.
- **Virtual die renaming** — Die settings dialog now has a name field for virtual dice.
- **Die settings: narrow-screen layout** — Color picker controls and threshold fields now wrap onto multiple lines on narrow screens instead of overflowing.

## 0.12.9

### Features

- **Rolling Flash (Pixels)** — New rolling flash feature for Pixels dice. You can now configure a custom color and animation (Strobe, Pulse, or Breathe) that triggers automatically while the die is rolling.
- **Unified Color Picker** — The die settings dialog now features a unified color picker that lets you switch between configuring the result blink color and the rolling flash color.
- **Preview Animations** — Added a "Preview" button in die settings to test both the result blink and the rolling flash animation directly from the dialog.
- **Virtual Dice Management** — Added an option to remove virtual dice from the dice list.

### Bug Fixes

- **Disconnect logic** — Fixed an issue where disconnecting a die would sometimes fail to remove it from the internal application state.
- **Pixels: dType persistence** — Improved reliability of die type (e.g. d20, d6) restoration when reconnecting Pixels dice.
- **Rolling notifications** — Fixed a bug where rolling flash would sometimes re-trigger on repeated BLE notifications of the same rolling state.

## 0.12.8

### Bug Fixes

- **BLE: Die detection** — Improved reliability of GoDice and Pixels identification on Android by caching device names across scans. Re-scans that return null names (common on Android) now correctly resolve to the previously identified device.
- **Pixels: stability** — Fixed a potential crash when receiving unknown message types from Pixels firmware.

## 0.12.7

### Bug Fixes

- **GoDice: macOS and Web connection** — GoDice dice are now discoverable on macOS and Web. The BLE scan was filtering by service UUID only; GoDice does not advertise its UART service UUID, so it was invisible to CoreBluetooth and Web Bluetooth. Scan now also filters by device name prefix (`GoDice_`), which is how the official GoDice SDK discovers dice.
- **GoDice: blink timing** — GoDice LED blink on-time and off-time were 10× too long (2500 ms instead of 250 ms) due to a unit conversion error in the timing calculation.
- **GoDice: concurrent blink** — Multiple GoDice now receive blink commands simultaneously instead of sequentially when a rule triggers a blink on all dice.
- **GoDice / Pixels: notify subscription** — Removed `cancelOnError` from BLE notify stream subscriptions. A transient GATT error would permanently kill the subscription, leaving the die appearing connected but silent.
- **Web: scan spinner** — The scan progress spinner now dismisses immediately after the browser device picker closes and the die connects, instead of running for an additional 6 seconds.

## 0.12.4

### Features

- Die color selector — choose a custom blink color per die from the die settings dialog.
