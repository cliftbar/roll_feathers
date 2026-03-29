# Spec: Make Threshold and Modifier Configurable in UI for Parsed Rules

## Background / Current State
- The parser/DSL supports `$THRESHOLD` and `$MODIFIER` placeholders and an `offset` transform that consumes `$MODIFIER`.
  - `parser.dart`: `runRule(..., {int threshold = 0, int modifier = 0})` with replacement of `$THRESHOLD` and `$MODIFIER`.
  - `parser_rules.dart`: sample rules use `with offset $MODIFIER`.
- The UI does not expose controls to set these parameters; rolls are evaluated with defaults:
  - `roll_domain.dart`: calls `ruleParser.runRule(r.script, _rolledDie.values.toList());` without `threshold`/`modifier`.
  - `script_screen.dart`: add/edit dialogs only edit rule text and enabled state.
  - `app_settings_screen_vm.dart`: manages scripts CRUD; no state for threshold/modifier.

Conclusion: Users cannot currently set Threshold or Modifier; both default to 0 at evaluation time.

## Goals
1. Allow users to configure a global Threshold and Modifier used when evaluating parsed rules.
2. Optionally support per-rule overrides (stretch goal, phase 2).
3. Persist settings and apply them consistently during roll evaluation.

## Non-Goals (for Phase 1)
- No changes to DSL syntax.
- No per-die or per-session ad hoc inputs beyond the global values.

## UX Requirements
- Add two numeric inputs in Settings (Drawer):
  - Modifier (integer, can be negative)
  - Threshold (integer, >= 0)
- Provide quick-access in main Dice screen toolbar for adjusting Modifier (optional small stepper +/-).
- Show current values somewhere unobtrusive (e.g., badge or subtitle under “Rules”).

## Data Model & Persistence
- AppRepository additions:
  - getModifier(): Result<int>
  - setModifier(int): Result<void>
  - observeModifier(): Stream<int>
  - getThreshold(): Result<int>
  - setThreshold(int): Result<void>
  - observeThreshold(): Stream<int>
- Persist alongside existing settings (same mechanism used for theme/keepScreenOn).

## Domain Changes
- RollDomain: when finalizing a roll, pass the configured values to the parser:
  - ruleParser.runRule(r.script, rolls, threshold: currentThreshold, modifier: currentModifier)
- Source of truth for current values: subscribe to AppRepository streams in the appropriate ViewModel(s) and expose to RollDomain or inject via Di.

## UI Changes
1. App Settings
   - In `AppSettingsWidget` add a new card/section “Rule Parameters” with:
     - TextField or Stepper for Modifier (supports negative).
     - TextField or Stepper for Threshold (>= 0).
   - Wire to `AppSettingsScreenViewModel` commands `setModifier`, `setThreshold`.
2. Dice Screen (optional quick control)
   - Add small +/- controls for Modifier next to existing controls.
   - Updates persist to AppRepository and reflect immediately in subsequent evaluations.

## ViewModel Changes
- AppSettingsScreenViewModel:
  - State: `int modifier`, `int threshold`.
  - Subscriptions to `observeModifier()` and `observeThreshold()`.
  - Commands: `setModifier(int)`, `setThreshold(int)`.
- DiceScreenViewModel (if quick control implemented): reuse same streams/commands.

## Parser Integration
- No changes required to parsing logic; ensure `$MODIFIER` and `$THRESHOLD` placeholders are present in scripts as needed.

## Testing Strategy
- Unit Tests
  - Verify that when modifier/threshold are set in repository, `RollDomain` passes them to `runRule`.
  - Parser eval uses `$MODIFIER` replaced correctly (e.g., `with offset $MODIFIER`).
- Widget Tests (optional)
  - Settings UI updates repository and reflects in ViewModel.

## Edge Cases
- Empty scripts or scripts not using placeholders should still evaluate normally.
- Negative modifier values should be accepted.
- Large values: clamp threshold to sensible range if necessary (e.g., 0–1000) to avoid UI errors.

## Implementation Steps (Phase 1)
1. AppRepository interface + implementation: add get/set/observe for modifier and threshold.
2. AppSettingsScreenViewModel: subscribe to new streams; add commands.
3. AppSettingsWidget: add inputs for modifier/threshold.
4. RollDomain: thread current values into `runRule` calls.
5. Tests per above.

## Phase 2 (Optional)
- Per-rule parameters: extend `RuleScript` to include optional overrides; UI to edit these per script; evaluation picks per-rule else global default.
