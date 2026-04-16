# Changelog

## Unreleased

### Features

- **Soundclip targets** — DSL rules now support `on result [range] soundclip <name>`. Plays the named clip from the library when the result range matches. Silent no-op if the clip name is not found.
- **Sound Clips library** — New "Sound Clips" screen in app settings to import, rename, preview, and delete audio clips from the library.
- **Global sound effects** — App-level rolling and rolled sounds that play on every roll event. Configurable per-clip from the Sound Clips screen, with independent enable toggles and a hard mute that silences all audio including rule soundclips.
- **Queue depth** — Sound clips queue sequentially up to a configurable depth (default 3); excess clips are silently dropped.
- **Per-die sound opt-out** — New "Use global sound effects" toggle in die settings. When off, the die does not trigger rolling/rolled sounds. Normal dice win: global sound fires unless all dice in the roll have opted out.
- **Webhook targets** — DSL rules now support `on result [range] webhook [GET|POST] <url>`. On match, fires an HTTP request to the configured URL. POST sends a full JSON payload with rule name, timestamp, aggregate value, matched range, result dice, all dice, and co-actions. GET appends `aggregate` and `rule` as query params. Errors are caught and logged; dice behavior is never interrupted.

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
