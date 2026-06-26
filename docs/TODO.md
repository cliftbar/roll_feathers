# Open Issues & TODOs

## Webhook / Discord Targets

### Test helper consolidation
`_Recorder` (MockClient + request/body capture) is duplicated across
`dsl_webhook_evaluation_test.dart` and `dsl_discord_evaluation_test.dart`. Extract to
`test/helpers/`.

`DslTestRunner` in `dsl_test_harness.dart` constructs `WebhookDomain()` with no mock client, so
any rule containing a live webhook target would hit the network in tests. Pass a mock or no-op
client via an optional parameter.

## Code Quality

### No test for malformed webhook URL
`WebhookDomain.fireWebhook` handles `Uri.parse` exceptions gracefully but there is no test
confirming the warning log fires and no exception propagates to the caller.

**File:** `test/domains/roll_parser/dsl_webhook_http_test.dart` (add a case)

## Pixels Animations & Profile Editor

Deferred work and known limitations from the Pixels profile/animation effort
(branch `cb_pixels_profile`). See also `docs/specs/pixels_firmware_capabilities.md`.

### Deferred features

- **RemoteAction bridge (die → app)** — A profile rule action `Action_RunOnDevice`
  makes the die send `MessageRemoteAction(actionId)` over BLE. The firmware sends it
  and `MessageRemoteAction` is defined in `pixels.dart`, but `_readNotify` in
  `dice_sdks.dart` has **no `remoteAction` case**, so it's silently dropped (harmless,
  no crash). Wire up: a receive handler + an `actionId → effect` registry, then connect
  `PixelActionSpeakText` and sound clips. The soundclip design assumes this bridge.
  Low–moderate effort (message + serialization already exist).
- **Gradient editor** — custom multi-stop gradient authoring. The editor only offers 5
  fixed presets (rainbow/fire/water/solid/two-color). Gradients drive Cycle/Gradient/
  Noise/Normals/GradientPattern, so this is the highest-leverage authoring addition.
- **Software animation preview / virtual-die rendering** — port the pixels-js `VirtualDie`
  animation evaluation to Dart so the editor previews any animation without a physical
  die, and virtual dice render the same animations as physical ones.
- **Pattern editor** — author custom per-LED patterns; today only `kBuiltinPatterns`
  are selectable for Keyframed / GradientPattern.
- **Worm animation type** (`Animation_Worm` = 11) — the dedicated firmware effect we
  currently approximate with Cycle. Low priority (Cycle already matches the official look).

### Editor gaps (smaller)

- **Per-animation `faceMask`** not exposed (only the rule/condition face mask is editable).
- **Action `faceIndex`** not exposed — can't choose "play on the rolled face vs. a fixed
  face"; only animIndex + loopCount.
- **Profile brightness** not editable in the editor UI.
- **In-editor preview** — previewing is only on the profiles-list screen, not while editing.

### Known firmware limitations (not fixable app-side)

- **FaceCompare condition is dead** on current firmware (enum slot 4 = `Condition_Unused1`,
  no handler in `behavior_controller.cpp`). No on-die "matched value X" detection — arbitrary
  result logic must stay app-side (the DSL). Our `PixelConditionType` reserves the slot but
  there is no usable condition for it.
- **(Resolved) friendlyName vs. external rename** — Pixels are now firmware-authoritative
  for their name: the true BLE rename writes it to the die, the app keeps only a transient
  in-session override for immediate feedback, and `asyncConvertToDie` no longer restores a
  saved name for Pixels (the advertised/firmware name wins on reconnect). Virtual dice are
  unaffected.

- **Rolling flash vs. on-die rolled animations are mutually exclusive.** App blinks and
  on-die animations blend additively, and the only app-reachable stop (`StopAllAnimations`)
  clobbers everything (there is no tag-scoped stop message). The stop is gated on
  `rollingFlashEnabled`, so today on-die profiles only work with rolling flash off.
  Coexistence needs a design change (e.g. a self-terminating rolling flash instead of an
  infinite app-side blink). See `docs/design/rule_effect_separation.md`.

### Testing / infra

- **Web `flutter drive` integration** is blocked by upstream flutter/flutter #181357
  (dwds `AppConnectionException`). Reproduced exhaustively (matched chromedriver, cleared
  Gatekeeper quarantine, clean state, Chrome closed). The app builds for web fine; it's a
  Flutter tooling bug. Web is instead covered by Playwright e2e (`e2e/`, `npm test`).
  Revisit if the upstream bug is fixed or on a CI runner with a known-good config.
- **macOS `all_tests` integration is brittle with a real die present** — the `core_dice`
  "starts with no dice" test fails because the launched app auto-connects the physical die.
  Pass `--dart-define=INTEGRATION_TEST=true` (uses `NoopBleRepository`) or make the test
  tolerate a connected die.
- **Playwright narrow-screen specs can't catch Flutter RenderFlex overflow** (release web
  doesn't throw, and overflow isn't exposed to the DOM) — they verify control presence at
  each viewport, not the absence of overflow.
- **dddice live `@integration` Playwright tests** (4) are skipped without `DDDICE_TOKEN` /
  `DDDICE_ROOM` env vars.

