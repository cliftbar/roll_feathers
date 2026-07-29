# Changelog

## 0.15.0

### Breaking Changes

- **Rule scripts must end with a `report` clause** — Every rule now declares the single value the roll is recorded as: `report <sum|min|max|avg|count> over <@selection|$ALL_DICE>`, written as the last clause. Previously that value fell out of whichever `use` block happened to be evaluated last, which was frequently the wrong one — all three High/Low rules reported the *minimum* die on every roll (a 6/1/3 roll recorded **1**), while the dice recorded alongside it came from a different block entirely. A `use` block's aggregate now only decides whether its `on result` ranges match; the reported value comes from the `report` clause. **Rules saved before this change will not parse.** They are logged and skipped — the rest of your rules still run and the roll is still recorded — but each needs a `report` line added. All built-in rules have been updated.

### Features

- **Rules report meaningful values** — High/Low rules now report the roll's total instead of the minimum. `Doubles`, `Duplicates`, and `All Above Threshold` report the total of the dice they selected rather than *how many* they selected, so a pair of 4s reads 8 rather than 2. Advantage and Disadvantage continue to report the max and min, which is correct for them.

### Bug Fixes

- **Android: flashing a Pixels profile silently corrupted it** — Android is the only platform where the BLE ATT MTU must be requested explicitly; it defaults to 23 (a 20-byte payload) and `universal_ble` never negotiates on its own, while CoreBluetooth (macOS/iOS) and the browser negotiate at connect. Every message over 20 bytes was therefore truncated in both directions. Animation transfer writes are 104 bytes, so flashed profiles landed on the die as garbage — *while reporting complete success at every step*, because the chunk offset lives in the first four bytes and survives truncation, so each chunk still acked. The app now requests an MTU at connect on Android (dice grant 128), and the post-transfer hash check that catches this runs unconditionally instead of only under debug logging. Verified against a real d20 on an Android device: all built-in profiles now flash with a matching DataSet hash.
- **Android reported 0% battery for every Pixels die** — Same root cause: the truncated `IAmADie` message lost its trailing battery fields. Fixed by the MTU negotiation above.
- **A rule with no matching result hijacked the roll** — A rule claimed a roll as soon as its `for roll ...` die-matcher accepted the dice, without checking whether any `on result` range actually matched. `Doubles` is `for roll *d*`, so it claimed *every* roll and recorded its duplicate count — **0** when there was no pair — in place of the roll's natural sum, while also preventing every rule after it from running. Rolling 1, 2, 3 with Doubles enabled recorded a result of 0 instead of 6. A rule must now produce a result to claim the roll.
- **A broken rule no longer destroys the roll record** — Rule evaluation runs before the roll is recorded, and a rule that failed to parse took the whole roll down with it. Such a rule is now reported and skipped, and the roll is still recorded.

### Internal

- **`report` clause and per-block outputs** — `report` is a required trailing element of the v1.1 grammar, so both a missing clause and a misplaced one are rejected at parse time. `ParseResult.blockOutputs` exposes a `UseBlockOutput` per `use` block in script order — including blocks that matched nothing — carrying that block's selection token, its own aggregate, whether any range fired, and its selected dice. Nothing consumes it yet. `ParseResult.matchedResult` distinguishes "the die-matcher accepted this roll" from "the rule produced a result", and `rolledEvaluated` now carries the acted-on selection rather than being a duplicate of `allRolled`.
- **ATT MTU negotiated on Android** — `UniversalBleDevice.setDeviceUuids` requests an MTU of 247 before any message traffic, gated on `PlatformInfo.isAndroid` and wrapped in its own error handling so a refusal degrades to the previous behaviour rather than breaking pairing. The granted value is logged, at SEVERE if it falls below what a full bulk-transfer chunk needs. It lives in the device wrapper rather than `BleUniversalRepository._connectDevice` because the live-die integration tests connect directly and would otherwise bypass it. A comment on `PixelTransfer.maxChunkSize` records the resulting ceiling: raising it past 121 silently re-breaks Android.
- **Profile transfers always verify their hash** — Comparing our computed DataSet hash against the die's stored hash was gated behind FINE logging, which is precisely why the Android corruption shipped unnoticed. It now always runs, logging SEVERE on mismatch. It deliberately does not throw: the bytes are already on the die either way, and failing the call would turn a silent problem into a broken flash button on platforms where this has always worked. The byte-level hex dump stays behind FINE.
- **`$MAX` / `$MIN` no longer break the structural parse** — Those variables are only known at evaluation time, so the first parse left them in place and the block containing them failed. That passed silently before; with `report` required immediately after the blocks it became a hard rejection of any rule using them. The structural parse now substitutes a placeholder, and evaluation still does the real substitution and reparse.
- **Lint pass** — `dart fix` across the touched files (deprecations, import and identifier lints) and `dart format` on the files changed by the DSL work.

## 0.14.0

### Features

- **Pixels LED animation profiles** — Full management of the LED animation profiles on [Pixels](https://gamewithpixels.com) dice. Browse a library of built-in profiles (ported from the official app and byte-for-byte hash-identical to it), flash one to a connected die, and see at a glance which profile is currently on the die — matched against the die's reported DataSet hash. A profile editor lets you create, duplicate, edit, import animations from other profiles, and live-preview an animation on a connected die. Animations and rule conditions (rolled face, rolling, hello/goodbye, connection state, battery state, handling, crooked, idle) are all editable. Built-in profiles are die-type-correct: they generate the right face masks for every Pixels die type — d4, d6, d8, d10, d00, d12, d20 — while staying hash-matched to the official app per type.
- **Physical Pixels die rename** — Renaming a Pixels die now issues a real BLE rename and waits for the die to confirm before updating the UI; the firmware name is authoritative (the app no longer keeps a separate stored name for Pixels). Virtual and GoDice dice keep their app-stored names.

### Bug Fixes

- **Pixels rolled face values wrong for d10 / d00** — A rolled face was always decoded as `faceIndex + 1`, correct for d4/d6/d8/d12/d20 but wrong for d10 (should be 0–9) and d00 (should be 0/10/…/90). Face-value decoding now goes through `PixelFaces.faceFromIndex(index, dieType)` in the `PixelDie` driver, so results, rules, webhooks, and dddice all see the correct value for every die type. d4/d6/d8/d12/d20 are unchanged.
- **On-die "rolled" animation clobbered by the app** — When the app's rolling-flash effect was disabled, the app still sent `StopAllAnimations` on the `rolled` telemetry, which killed a die's own on-die "rolled" animation. The stop is now gated on `rollingFlashEnabled`.
- **Profile editor crash on a rule with no animations** — Saving/previewing a rule whose profile had no animations could throw; the editor now guards the animation-index lookups and roll-callback registration.
- **Black frame on startup** — The app now renders a lightweight splash immediately and initializes BLE/HA/HTTP/SharedPreferences asynchronously, instead of showing a black window while async init completes.

### Internal

- **Pixels profile/animation feature follows the layered architecture** — The whole feature is the worked example for `docs/architecture.md`: UI (`ui/pixels/`, MVVM + Command) → `PixelProfileDomain` → `PixelProfileRepository` (data) + `PixelDieService` (the die, an external system) + pure logic in `core/pixels/animation_import.dart`. SDK files are grouped under `dice_sdks/pixels/`.
- **`PixelFaces` — Pixels face semantics in the SDK** — `dice_sdks/pixels/pixel_faces.dart` is a current-firmware port of the official `DiceUtils`: the canonical face↔index↔mask mapping per die type (`indexFromFace`, `faceFromIndex`, `faceMask`, `dieFaces`, `highestFace`, …). Used by both the die-type built-in profile templates and rolled-value decoding.
- **Built-in profiles are die-type templates** — `BuiltinProfile.build(PixelDieType)` rebuilds each profile's rule conditions as logical face selections (top / non-top / halves / thirds / per-face) via `PixelFaces`, mirroring the official `createLibraryProfile`. Animation data stays die-agnostic; d20 output is byte-identical to before.
- **Byte-for-byte hash parity, all die types** — `pixels_official_hash_parity_test.dart` asserts every built-in profile's `DataSet` hash against official pixels-js ground-truth for all 7 die types (105 hashes). A new parameterized `pixels_official_transfer_roundtrip_test.dart` flashes every built-in × die type through the full `PixelDieService` → `PixelsDieSimulator` transfer path (chunking, acks, reassembly) and checks the reassembled bytes and hash (119 cases).
- **Pixels SDK constants consolidated** — `dice_sdks/pixels/pixels_constants.dart` is the single home for shared protocol constants: `kFaceMaskAll`, `PixelAnimFlags`, normals/noise color-override modes, the condition flag classes (`PixelBatteryFlags` / `PixelHelloFlags` / `PixelConnectionFlags`), and bulk-transfer tuning (`PixelTransfer`). Removes literals/named-constant duplication across the SDK. Little-endian byte writers were hoisted to `TxMessage` (`setU16`/`setU32`).
- **Platform detection centralized behind `PlatformInfo`** — `util/platform_info.dart` resolves the host platform once at the composition root (`DiWrapper.initDi`) and is injected wherever behavior depends on it: the BLE repository, HA repository, both HTTP client providers, and the UI (via VM `isWeb` getters). No `Platform.is*` / `kIsWeb` / `kIsWasm` checks remain outside `platform_info.dart`.
- **Pixels BLE transfer protocol + test simulators** — Fixed the bulk-transfer (`TransferAnimationSet` → chunked `BulkData` → ack/finished) protocol and added live-die integration tests. Two fakes stand in for hardware: a message-level `PixelsDieSimulator` (stores flash bytes, computes and reports the DataSet hash) and a BLE-device `PixelsBleDeviceSimulator` (die-type-aware `IAmADie`/`RollState`). BLE message request/response correlation was consolidated into `GenericBleDie`.

## 0.13.1

### Features

- **Remove-dice confirmation dialogs** — The "Remove Virtual Dice" and "Remove All Dice" drawer actions now prompt before acting, and the empty state hints how to add or pair dice.

### Bug Fixes

- **`$THRESHOLD` / `$MODIFIER` ignored in evaluation reparse** — The evaluator's `_prepareEvaluation` reparse (which substitutes `$MAX`, `$MIN`, `$ROLLED` just before evaluation) did not substitute `$THRESHOLD` or `$MODIFIER`, so rules using those variables in `with over`, `with dupes`, or similar transforms silently produced wrong selections. Both variables are now included in the reparse substitution. Rules affected: `nDupes`, `allAboveThreshold`, `maxWithModifier`.
- **Die-name whitespace in `dieParser` caused roll matching to always fail** — `dieParser` used `.flatten()` which captures the entire matched span including surrounding whitespace consumed by adjacent `.trim()` calls. This produced tokens like `"*d10\n\n  "` rather than `"*d10"`, so `_checkRollConditions` never matched the clean roll names from BLE events and the rule's use-block never ran. Fixed by adding `.map((s) => s.trim())` to `dieParser`. Rule affected: `averagePassFailD10` (and any rule using wildcard count matchers like `*d10`).
- **Layout overflow on narrow screens** — Fixed `RenderFlex` overflow errors on the main dice screen header and the roll controls row on small/narrow viewport widths.
- **Port-in-use error swallowed on API server start** — `SocketException` on `HttpServer.bind` (e.g. port already taken) was previously uncaught; it is now caught and logged.
- **Windows build failure on newer MSVC** — `permission_handler_windows` pulls in `<experimental/coroutine>`, which MSVC 14.51+ flags as a hard error. The Windows build now defines `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` to suppress it.

### Internal

- **`Color.value` deprecation** — Replaced uses of the deprecated `Color.value` property with `Color.toARGB32()`.
- **`SharedPreferences` / `SharedPreferencesAsync` in tests** — Replaced deprecated `SharedPreferences.setMockInitialValues` with `SharedPreferencesAsyncPlatform.instance` mock setup where required by updated plugin APIs.
- **README updated** — Added dddice, webhooks, and Discord to Features; added Webhooks & Discord and dddice Integration sections; rewrote Rule Scripting section with current v1.1 DSL syntax (prior content used the removed v1.0 syntax).
- **docs/TODO.md cleaned up** — Removed resolved items: iOS ATS, parse/evaluate split, PackageInfo logging, FormatException logging, GET webhook payload doc.

## 0.13.0

### Features

- **dddice integration** — Physical dice rolls can be mirrored to a [dddice](https://dddice.com) virtual tabletop room in real time. Enable in settings, supply an API key (or leave blank for guest mode as `bees`), pick a room, and optionally assign a theme per die. Guest sessions auto-create a temporary room on first roll.
- **Integration test suite** — Flutter integration tests covering BLE, dddice, and Home Assistant flows added under `integration_test/`. A `DddiceMockServer` and `HaMockServer` stand-in for remote APIs during CI runs. The test script (`scripts/integration_tests.sh`) handles macOS, Android, and iOS targets.
- **dddice mock server** — `lib/testing/dddice_mock_server.dart` provides a local HTTP server that simulates the dddice API; used by both integration tests and unit tests.
- **HA mock server** — `lib/testing/ha_mock_server.dart` provides a local HTTP server that simulates the Home Assistant API.

### Internal

- **`buildApiHandler` extracted from `ApiDomainServer.create()`** — Integration tests can now exercise HTTP routes without binding a socket. Accepts an optional `port` parameter.
- **`DddiceRepository` accepts optional `baseUrl` override** — Allows tests to point at `DddiceMockServer` without touching production DI.
- **`DDDICE_BASE_URL` dart-define** — DI reads `--dart-define=DDDICE_BASE_URL` at compile time and passes it to `DddiceRepository` when non-empty, enabling test builds to hit a local mock server.

## 0.12.19

### Bug Fixes

- **HTTP webhook URLs now work on iOS** — Added `NSAllowsArbitraryLoads` to `NSAppTransportSecurity` in `Info.plist`. Previously, iOS App Transport Security silently blocked all plain-HTTP webhook requests regardless of app settings.

### Internal

- **Ignore worktrees** — Added `.worktree/` to `.gitignore`.
- **Split `RuleParser` out of `RuleEvaluator`** — DSL parsing (data classes, constants, static petitparser combinators, and `parse()`) now lives in a dedicated `RuleParser` class with static-only access. `RuleEvaluator` retains rule management and roll evaluation. No behaviour change; all 260 tests pass.
- **PackageInfo failure now visible** — `PackageInfo.fromPlatform()` errors were silently swallowed; they now `debugPrint` so unexpected platform failures are diagnosable.
- **`FormatException` from malformed webhook URLs logged distinctly** — `fireWebhook` previously caught URL parse errors and network errors in the same `catch` block with the same message; `FormatException` now gets its own branch with a URL-specific warning.
- **GET webhook payload documented** — `RollResultDTO.toQueryParams()` now carries a comment noting that GET only sends `rule` + `aggregate`; consumers needing per-die detail must use POST.

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
