# Windows BLE Scan + Connect Stability Spec

## Context
- During scans on Windows, dice sometimes blink blue (device believes it’s connected) but do not appear in the app.
- Current implementation connects inside the scan callback, which can race with WinRT scanning and cause ghost connections.

## UX Requirements
- Keep “connect while scanning” behavior.
- Multiple dice may be present; list should update as devices are discovered (emit to UI immediately on discovery).

## Constraints & Notes
- Windows advertisement packets may omit complete 128‑bit service UUIDs; service‑filtered scans can miss devices.
- WinRT can be sensitive to scan/connect overlap; small scheduling tweaks reduce flakiness without pausing global scan.

## Proposed Changes Ranked by Complexity (lowest → highest)
1. Honor `scan(timeout)` parameter instead of hardcoded 10s
   - Replace fixed `Timer(Duration(seconds: 10), ...)` with `Timer(timeout ?? const Duration(seconds: 5), ...)`.
   - File: `lib/repositories/ble/ble_universal_repository.dart`

2. Increase BLE timeouts on desktop (Windows/macOS/Linux)
   - Set `UniversalBle.timeout = Duration(seconds: 20–30)` during init on desktop.
   - File: `lib/repositories/ble/ble_universal_repository.dart`

3. Avoid service filters on Windows during scan
   - In DI for Windows, call `scan(services: const [])` instead of filtering by UUIDs.
   - File: `lib/di/di.dart`

4. Emit device to UI immediately on discovery (before connect) and keep it listed
   - Ensure discovered devices are added/emitted before any connect logic runs.
   - File: `lib/repositories/ble/ble_universal_repository.dart`

5. Add simple per‑device debounce (short window, e.g., 2s)
   - Track last‑seen timestamp per `deviceId` to ignore rapid rediscoveries.
   - File: `lib/repositories/ble/ble_universal_repository.dart`

6. Guard rediscoveries until the current attempt settles or scan ends (session‑based guard)
   - Add `scanSessionId`, `_deviceGuard`, and `_connecting` flags; ignore rediscoveries while a connect pipeline is active for that device (or until scan completes).
   - File: `lib/repositories/ble/ble_universal_repository.dart`

7. Per‑device connect throttle (150–300ms) before calling `connect()` while scan continues
   - Insert a tiny delay before `UniversalBle.connect(deviceId)` to avoid scan/connect collision on Windows.
   - File: `lib/repositories/ble/ble_universal_repository.dart`

8. Make per‑device connect attempts serial with limited backoff retries
   - Maintain `_connecting` flag; implement 2–3 retries with exponential backoff; cool‑down after failure.
   - File: `lib/repositories/ble/ble_universal_repository.dart`

9. Track and emit per‑device connection status (discovered/connecting/connected/failed)
   - Extend `UniversalBleDevice` or maintain side state; emit updates on the same stream so UI reflects progress/failure.
   - File: `lib/repositories/ble/ble_universal_repository.dart` (+ optional UI)

10. Stop scan per‑device before connect while keeping global scan (advanced scheduling)
    - Simulate per‑device pause via guards if library lacks true per‑device stop.
    - File: `lib/repositories/ble/ble_universal_repository.dart`

11. Platform‑specific DI path mirroring iOS on Windows (wait for poweredOn, then scan)
    - Add availability listener; start scanning once powered on.
    - File: `lib/di/di.dart`

12. Full reconnect/backoff pipeline with manual/auto‑disconnect differentiation
    - Distinguish manual vs. OS disconnect; capped auto‑reconnect with backoff; update device status.
    - File: `lib/repositories/ble/ble_universal_repository.dart`

## Minimal First Pass Recommendation
- Implement 1 → 5 and 7 first. Reassess stability; add 6, 8, and 9 if needed.
