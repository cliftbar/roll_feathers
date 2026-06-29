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
- **Gradient editor** — custom multi-stop gradient *authoring*. The editor only offers 5
  fixed presets (rainbow/fire/water/solid/two-color). Gradients drive Cycle/Gradient/
  Noise/Normals/GradientPattern, so this is the highest-leverage authoring addition.
  (No longer *lossy*: a bespoke source gradient now round-trips as `_GradPreset.custom`
  — preserved verbatim, shown as "Custom (from source)" — instead of snapping to Rainbow.
  Editing it still requires picking a preset; full multi-stop authoring is the open work.)
  Note: the dialog also preserves non-exposed fields (`animFlags`, and `faceMask` where
  present) across an edit via `_preserveHiddenFields`, so editing one parameter no longer
  resets the rest (e.g. the Magic cycle's `animFlags: 2`).
- **Software animation preview / virtual-die rendering** — port the pixels-js `VirtualDie`
  animation evaluation to Dart so the editor previews any animation without a physical
  die, and virtual dice render the same animations as physical ones.
- **Pattern editor** — author custom per-LED patterns; today only `kBuiltinPatterns`
  are selectable for Keyframed / GradientPattern.
- **Worm animation type** (`Animation_Worm` = 11) — the dedicated firmware effect we
  currently approximate with Cycle. Low priority (Cycle already matches the official look).
- **Die-aware rule editor (Part D)** — built-in *profiles* are now die-type-correct
  (`build(PixelDieType)` via `PixelFaces`, hash-matched per type), but the rolled-condition
  *editor* still hardcodes d20: the dialog defaults `_faceMask` to `0xFFFFF` and renders face
  chips 1–20. For user-authored profiles on non-d20 dice it should pull the connected die's
  faces from the domain (`dieFaces` / `facesToMask` / `maskToFaces`, delegating to
  `PixelFaces`) and render chips for that die's faces, defaulting to all-faces — logic in the
  domain (UI → domain), dialog keeping local form state. This makes *authoring* die-correct;
  it does **not** make one saved profile auto-adapt across face counts (that needs a logical
  selector instead of a concrete mask + rebuild-per-die, and is beyond the official app's
  per-die-type model).

### Code review follow-ups (PR #49)

- **Abstract `PixelProfileRepository` — does it earn its keep?** Confirm the interface is
  justified by a real fake/noop seam in tests, or collapse it onto the concrete
  `SharedPrefsPixelProfileRepository`.
- **Realistic simulator battery handling** — tracked under *Testing / infra* below.
- **Split official animations into their own file** — `pixels_builtin_animations.dart` is
  already the dedicated animation library (stray protocol constants moved to
  `pixels_constants.dart`); the hash-locked content actually lives in
  `pixels_builtin_profiles.dart` (guarded by the parity + round-trip tests). An explicit
  hash-compat-labeled split of the animation library is optional polish, not yet done.

### Editor gaps (smaller)

- **(Code cleanup, low priority) Animation editor dialog "fat state".**
  `_AnimationEditorDialogState` holds ~30 flat fields across all 9 animation types
  with large init/build switches. A per-type sub-model (one class per type with
  `build()` + `fields()`) would cut the coupling. Purely cosmetic — deferred
  because it's a sizeable rewrite of working, tested UI with no functional gain
  and no test coverage for every type's field round-trip. Best done alongside the
  gradient editor, which will reshape this dialog anyway.
- **Per-animation `faceMask`** not exposed (only the rule/condition face mask is editable).
- **Action `faceIndex`** not exposed — can't choose "play on the rolled face vs. a fixed
  face"; only animIndex + loopCount.
- **Profile brightness** not editable in the editor UI.
- **(Resolved) In-editor preview** — the editor now has per-animation preview
  buttons and a live "Preview" action inside the animation dialog (gated on a
  connected die). The preview transport is centralized in
  `PixelsProfileTransfer.previewProfileAnimation` (uploads the whole set + plays
  one index, so Sequence sibling references resolve); both the editor and the
  profiles-list screen call it, adding only their own progress/feedback UI.

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
- **More realistic battery handling in `PixelsBleDeviceSimulator`** (PR #49 review) — today
  `setBattery` just stamps a percent + `BatteryState`. Plan a more lifelike model: gradual
  drain over time, charging ramp-up, low/critical thresholds that drive `BatteryState`
  transitions automatically, and maybe a `done`/`error` charging path. Needs a short design
  pass before implementing.

