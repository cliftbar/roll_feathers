# GoDice macOS / Web BLE Fixes

## Problems fixed (branch: cb_godiceFixes)

### 1. GoDice not discovered on macOS (and Web)

**Root cause:** Scan was filtering by service UUID only (`6e400001-…`). macOS CoreBluetooth returns only devices that *advertise* that UUID in their advertisement packet. GoDice does not include the NUS service UUID in its advertisements — the official JS SDK scans by name prefix (`GoDice_`), not service UUID.

**Fix:** Added `withNamePrefix: ['GoDice_']` to `ScanFilter` (OR'd with `withServices`). Both Pixels (found by service UUID) and GoDice (found by name) are now discovered.

Files: `ble_universal_repository.dart`, `ble_repository.dart`, `app_settings_screen_vm.dart`, `di.dart`

---

### 2. Notify subscription silently died on stream errors

**Root cause:** `cancelOnError: true` on both `GoDiceBle` and `PixelDie` notify stream subscriptions. Any transient BLE GATT error permanently cancelled the subscription — die stayed "connected" but received no further notifications.

**Fix:** Removed `cancelOnError: true` (Dart default is `false`).

File: `dice_sdks.dart` — `GoDiceBle._init()` and `PixelDie._init()`

---

### 3. GoDice blinked sequentially with multiple dice

**Root cause:** `result_targets.dart:blink()` awaited `dd.blink()` per-die in a for-loop. With multiple GoDice, commands were dispatched one at a time.

**Fix:** Changed to `Future.wait` so all dice receive the command concurrently. (`sequence` already did this.)

File: `result_targets.dart:blink()`

Note: `writeMessage` uses `withoutResponse: true`. GoDice write characteristic (`6e400002`) supports `WRITE_WITHOUT_RESPONSE` — confirmed working on macOS and Android. The write type was not the cause of the original macOS connection failure; that was entirely the scan filter (issue 1 above).

---

### 4. Web scan spinner persisted after Chrome dialog closed

**Root cause:** `_startBleScan()` always set a 6-second countdown timer after `scan()` returned. On web, `scan()` blocks until the browser dialog closes and the device connects, so the timer fired 6 seconds after the scan was already complete.

**Fix:** On `kIsWeb`, reset `_scanInProgress` immediately after `scan()` returns instead of using a timer.

File: `app_settings_screen_vm.dart:_startBleScan()`
