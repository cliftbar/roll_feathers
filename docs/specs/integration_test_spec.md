# Integration Test Spec — Flutter integration_test (Path 1)

## Setup

### pubspec.yaml addition
```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

### File structure
```
integration_test/
  app_test.dart          # main entry point, groups all suites
  helpers/
    pump_app.dart        # shared app-pump helper (starts app, awaits settle)
    die_helpers.dart     # add/remove virtual die helpers
```

### Run command
```bash
flutter test integration_test/app_test.dart -d macos   # or -d <simulator-id>
```

### App startup assumptions
- App starts with no dice, no saved settings (integration_test gets a fresh SharedPreferences context)
- BLE is not available in simulator — BLE-dependent UI paths should be verified as disabled/absent rather than tested for function

---

## Out of scope (BLE-only, cannot test without hardware)
- Scanning for and connecting a real die
- Rolling flash blink on physical Pixels die
- Home Assistant entity blink
- Disconnect BLE Dice (button is present but BLE will be disabled in simulator)

---

## Test Suites

---

### Suite 1: Initial state

**Purpose:** Verify the app opens correctly with no dice added.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 1.1 | App bar renders | Launch app | "Roll Feathers" title visible |
| 1.2 | Empty dice state | Launch app | "No dice added" text visible in left column |
| 1.3 | Empty roll history state | Launch app | "Make some rolls!" text visible |
| 1.4 | Roll button present | Launch app | "Roll" button visible |
| 1.5 | Add Die button present | Launch app | "Add Die" button visible |
| 1.6 | Auto-roll toggle present | Launch app | "Auto-roll" label visible with a Switch |

---

### Suite 2: Add virtual die

**Purpose:** Verify the add-die dialog flow and die list update.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 2.1 | Add Die dialog opens | Tap "Add Die" | Dialog appears with title "Add Virtual Die", "Die Name" field, "Number of Faces" field |
| 2.2 | Dialog defaults | Open dialog | Name field shows "VirtualDie", faces field shows "6" |
| 2.3 | Cancel closes dialog | Open dialog → tap "Cancel" | Dialog dismissed, no die added, "No dice added" still shown |
| 2.4 | Add d6 with default name | Open dialog → tap "Add" | Dialog closes, die tile appears in list ("VirtualDie") |
| 2.5 | Add die with custom name | Open dialog → clear name → type "Red D20" → change faces to "20" → tap "Add" | Tile appears labeled "Red D20" |
| 2.6 | Add multiple dice | Add die twice | Both tiles visible in list |
| 2.7 | Die count reflected | Add 3 dice | 3 tiles visible, "No dice added" gone |
| 2.8 | Faces field numeric only | Open dialog → type letters in faces field | Letters rejected, field stays numeric |

---

### Suite 3: Rolling virtual dice

**Purpose:** Verify manual roll and auto-roll produce roll results.

**Precondition:** At least one virtual die added.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 3.1 | Manual roll produces result | Add die → tap "Roll" | A result appears in Roll History panel |
| 3.2 | Roll history not empty after roll | Add die → tap "Roll" | "Make some rolls!" text gone |
| 3.3 | Roll result contains value | Add die → tap "Roll" | Roll history entry visible (RichText with numeric result) |
| 3.4 | Multiple rolls accumulate | Add die → tap "Roll" 3 times | 3 entries visible in roll history |
| 3.5 | Clear roll history | Roll once → tap "Clear" | Roll history empty, "Make some rolls!" returns |
| 3.6 | Auto-roll toggle off, Roll button still works | Toggle Auto-roll off → tap "Roll" | Result still appears |

---

### Suite 4: Settings drawer

**Purpose:** Verify drawer opens and contains expected controls.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 4.1 | Drawer opens via hamburger | Tap hamburger (Icons.menu) | Drawer slides open |
| 4.2 | Drawer header shows "Settings" | Open drawer | "Settings" text visible |
| 4.3 | Dark Mode toggle present | Open drawer | "Dark Mode" or "Light Mode" ListTile visible |
| 4.4 | Keep Screen On toggle present | Open drawer | "Keep Screen On" SwitchListTile visible |
| 4.5 | Add New Virtual Die present in drawer | Open drawer | "Add New Virtual Die" ListTile visible |
| 4.6 | Remove Virtual Dice present | Open drawer | "Remove Virtual Dice" ListTile visible |
| 4.7 | Remove All Dice present | Open drawer | "Remove All Dice" ListTile visible |
| 4.8 | Home Assistant Settings present | Open drawer | "Home Assistant Settings" ListTile visible |
| 4.9 | Rule Scripts present | Open drawer | "Rule Scripts" ListTile visible |
| 4.10 | Dark mode toggle changes theme | Open drawer → tap "Dark Mode" | Drawer closes, app switches theme |
| 4.11 | Keep Screen On toggles | Open drawer → tap "Keep Screen On" switch | Switch value flips |

---

### Suite 5: Remove dice (drawer actions)

**Purpose:** Verify virtual die removal actions.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 5.1 | Remove Virtual Dice clears virtual dice | Add 2 dice → open drawer → tap "Remove Virtual Dice" | Dice list empty, "No dice added" visible |
| 5.2 | Remove All Dice clears list | Add 2 dice → open drawer → tap "Remove All Dice" | Dice list empty |
| 5.3 | Drawer add virtual die works | Open drawer → tap "Add New Virtual Die" | Add die dialog appears |

---

### Suite 6: Single die settings dialog

**Purpose:** Verify opening and interacting with the per-die settings dialog.

**Precondition:** At least one virtual die ("VirtualDie") added.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 6.1 | Tap die tile opens settings dialog | Add die → tap die tile | Dialog appears with "VirtualDie Settings" title |
| 6.2 | Dialog has expected action buttons | Open settings dialog | "Cancel", "Save", "Preview" buttons visible; disconnect icon (Icons.link_off) visible |
| 6.3 | Cancel closes dialog | Open dialog → tap "Cancel" | Dialog dismissed |
| 6.4 | Save closes dialog | Open dialog → tap "Save" | Dialog dismissed |
| 6.5 | Brightness slider present | Open dialog | Widget with key `Key('brightness_slider')` visible |
| 6.6 | Color mode dropdown present | Open dialog | DropdownMenu visible |
| 6.7 | Switch to RGB/Sliders mode | Open dialog → select "RGB / Sliders" from dropdown | R, G, B fields visible |
| 6.8 | Switch to HSV mode | Open dialog → select "HSV / Square" | H, S, V fields visible |
| 6.9 | Switch to HSL mode | Open dialog → select "HSL / Square" | H, S, L fields visible |
| 6.10 | Face Count section shown for virtual die | Open dialog for virtual die | "Face Count" label and face count field visible |
| 6.11 | Rolling Flash section absent for virtual die | Open dialog for virtual die | "Rolling Flash" text not found |
| 6.12 | Disconnect button removes die | Open dialog → tap disconnect icon | Dialog closes, die removed from list |
| 6.13 | Save persists die in tile | Open dialog → tap Save | Die tile still visible after close |
| 6.14 | Custom face count accepted | Open dialog → change face count to "12" → tap Save | No crash; dialog closes |

---

### Suite 7: Home Assistant settings dialog

**Purpose:** Verify HA settings dialog opens and basic fields exist.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 7.1 | HA dialog opens from drawer | Open drawer → tap "Home Assistant Settings" | Dialog appears |
| 7.2 | HA dialog has Enable toggle | Open HA dialog | "Enable Home Assistant" toggle visible |
| 7.3 | HA URL field present | Open HA dialog | "Home Assistant URL" field visible |
| 7.4 | Cancel closes HA dialog | Open HA dialog → tap "Cancel" | Dialog dismissed |
| 7.5 | Save closes HA dialog | Open HA dialog → tap "Save" | Dialog dismissed |
| 7.6 | Fields disabled when HA disabled | Open HA dialog with HA disabled | URL, token, entity fields disabled |
| 7.7 | Fields enabled when HA toggled on | Open HA dialog → toggle Enable on | URL, token, entity fields enabled |

---

### Suite 8: Rule Scripts navigation

**Purpose:** Verify navigation to the script screen works.

| # | Test name | Steps | Expected |
|---|-----------|-------|----------|
| 8.1 | Rule Scripts opens a new screen | Open drawer → tap "Rule Scripts" | Drawer closes, new screen pushed |
| 8.2 | Back navigation returns to main screen | Navigate to scripts → press back | "Roll Feathers" app bar visible |

---

## Finder reference

| Element | Finder |
|---------|--------|
| App bar title | `find.text('Roll Feathers')` |
| Hamburger menu | `find.byIcon(Icons.menu)` |
| Auto-roll toggle | `find.text('Auto-roll')` |
| Add Die button | `find.text('Add Die')` |
| Roll button | `find.text('Roll')` |
| Roll History panel | `find.text('Roll History')` |
| Empty dice label | `find.text('No dice added')` |
| Empty history label | `find.text('Make some rolls!')` |
| Brightness slider | `find.byKey(Key('brightness_slider'))` |
| Disconnect icon | `find.byIcon(Icons.link_off)` |
| Color mode dropdown | `find.byWidgetPredicate((w) => w is DropdownMenu).first` |

## Notes on test isolation

- Each suite should re-pump the app from scratch or use `setUp` to add/remove dice as needed
- Virtual dice are in-memory only — no SharedPreferences cleanup needed between tests unless settings are explicitly saved
- Use `pumpAndSettle()` after taps; use `pump(Duration(milliseconds: 500))` for animation-heavy transitions
- Roll results are async — after tapping "Roll", use `pumpAndSettle()` to wait for the result to render

## Priority order for implementation

1. Suites 1–3 (core loop: add die, roll, see result)
2. Suites 4–5 (drawer and remove)
3. Suite 6 (single die settings)
4. Suites 7–8 (HA settings, navigation)
