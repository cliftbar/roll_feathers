# Changelog

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
