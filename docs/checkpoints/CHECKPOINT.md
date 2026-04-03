# Checkpoint: cb_dieColorSelector

## Branch state (2026-04-02)

Modified files:
- `lib/ui/die_screen/single_die_settings_dialog.dart`
- `lib/ui/die_screen/dice_screen_vm.dart`
- `lib/ui/die_screen/dice_screen.dart`
- `test/ui/single_die_settings_dialog_test.dart` (new)

---

## What was completed

### `single_die_settings_dialog.dart`
- Replaced `AlertDialog` with `Dialog` + `ConstrainedBox(maxWidth:420, maxHeight:85%)` — fixes `IntrinsicWidth` → `LayoutBuilder` debug-mode crash caused by `AlertDialog` + `DropdownMenu` combination
- `HSVColor _currentColor` is single source of truth for color state (renamed from `_hsvColor`)
- Four color modes (`_ColorMode` enum): `Hex / Wheel`, `ARGB / Sliders`, `HSV / Square`, `HSL / Square`
- Custom `_GradientTrackShape` replaces `ColorPickerSlider` for ARGB sliders (black→red, black→green, black→blue, transparent→opaqueColor for alpha)
- Inline 24px color preview dot in the Color/dropdown row
- Full numeric fields: R, G, B, A (0–255), H (0–360), S/V/L (0–100), Hex (6 char)
- Backspace-to-empty: `FocusNode.addListener` restores last valid value via `_updateControllers()` on blur
- `OverflowBar` for actions (wraps on narrow screens)
- `DropdownMenu` explicit `width: 185` to prevent overflow

### `dice_screen_vm.dart`
- `_blink` now passes `blinkColor` parameter to domain (was ignoring it and using `die.blinkColor`)

### `dice_screen.dart`
- Removed dead code: `_setRollType()`, `_rollMax`, `_rollMin`

### `test/ui/single_die_settings_dialog_test.dart`
- 23 widget tests, all passing
- Uses `showDialog` host pattern (not bare `Scaffold.body`) so `AlertDialog`/`Dialog` has proper overlay context
- `_selectColorMode` helper uses `find.byWidgetPredicate((w) => w is DropdownMenu).first` (type erasure workaround)
- Programmatic `FocusManager.instance.primaryFocus?.unfocus()` for blur testing (fields may be off-screen in test viewport)
- `sendKeyEvent` (not `sendKeyDownEvent`) for backspace — avoids `HardwareKeyboard` duplicate-key assertion

---

## Open issue: numeric fields uneditable in real macOS app

All 23 tests pass. User reports: "I still can't edit numeric fields in any mode."

`enterText` in widget tests bypasses real keyboard dispatch, so the bug is undetected by current tests.

**Hypotheses:**
1. `Slider` widget's keyboard handler intercepting keystrokes when it has (or retains) focus
2. `DropdownMenu` retaining focus after selection, blocking TextField focus acquisition
3. `SingleChildScrollView` event routing
4. `FilteringTextInputFormatter.digitsOnly` + `keyboardType: TextInputType.number` desktop interaction

**Next step:** Write tests using character-by-character `sendKeyEvent` (not `enterText`) to replicate real keyboard dispatch. If those fail, that's the repro — then fix. Also verify `focusNode` wiring in `_field()` builder is correct in the live widget tree.
