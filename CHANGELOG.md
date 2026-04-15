# Changelog

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
