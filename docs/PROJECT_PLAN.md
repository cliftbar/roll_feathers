# Roll Feathers — Project Review and Roadmap

Last updated: 2026-03-17

## Overview

Roll Feathers is a Flutter companion app for Bluetooth-enabled dice (Pixel Dice, GoDice) with optional virtual dice. It tracks rolls, can blink dice, integrates with Home Assistant to blink lights on events, and exposes a small HTTP API for the latest roll. Targets Android, macOS, Windows, and Web (with some features limited on Web).

## Current Features (from code and README)

- Device support
  - Scan/connect to multiple dice concurrently via BLE
  - Supported: Pixel Dice, GoDice, Virtual Dice
  - Virtual dice auto-roll simulation with configurable behavior
- Rolling and history
  - Track roll history (value, per-die results, timestamp)
  - Roll types: sum, max (advantage), min (disadvantage), rule-based custom rolls
  - Rolling lifecycle notifications via streams (started/rolling/ended)
- Visual feedback
  - Blink connected dice on events with chosen color (per supported SDK)
- Home Assistant integration
  - Optional HA connectivity (token + URL) via settings
  - Blink an HA light entity on rolls (entity can be targeted per die)
- HTTP API (non-Web platforms)
  - GET /api/last-roll → JSON with latest roll
  - Server binds on IPv4 0.0.0.0:8080; UI can display detected local IPs
- Cross‑platform
  - Android, macOS, Windows fully targeted
  - Web supported (BLE via universal provider; API server disabled)
- Rule scripting
  - Parser powered rules can compute results and mark rule name
  - Rules are loaded at startup (AppService + RuleParser)

## Code Structure (high level)

- lib/
  - di/: dependency initialization (platform-aware BLE, HA, API server)
  - domains/
    - die_domain.dart: discovery, lifecycle, and utilities for dice
    - roll_domain.dart: roll state machine, history, rule execution
    - api_domain.dart: HTTP server for latest roll (non-Web)
    - roll_parser/*: rule parsing logic and transforms
  - dice_sdks/: GoDice, Pixel protocols, and GenericDie abstractions
  - repositories/: BLE abstraction(s), Home Assistant, App repo
  - services/: AppService; HA services (API/config)
  - ui/: Material app, Dice screen, App settings, Script screen
  - main.dart: logging, DI bootstrap, runApp
  
Tests exist for SDKs (GoDice, Pixel) and parser pieces.

## Potential Bugs and Risks (static review)

1. DieDomain.blink switch without breaks/returns (risk: unintended fall-through or compile error)
   - File: lib/domains/die_domain.dart
   - switch(die.type) has three cases but no break/return after each case. In Dart, fall‑through is not permitted without labels; this likely either fails analysis or sends multiple messages and chooses the last blinker unexpectedly. Each case should return or break via separate blocks.

2. StreamController not closed in DieDomain.dispose (resource leak)
   - _diceSubscription is never closed. Should call _diceSubscription.close() during dispose.

3. RollDomain.create does not await init()
   - create() is async, but calls rollDomain.init() without await. Callers await create(), assuming readiness; rules might not be fully initialized, causing race conditions.

4. ApiDomainServer.getIpAddresses assumes addresses[0]
   - File: lib/domains/api_domain.dart
   - Uses e.addresses[0] without checking emptiness → potential RangeError on systems where an interface presents without addresses.

5. BLE repository init/scan sequencing
   - DI initializes BleUniversalRepository and calls init().whenComplete(() => scan(...)). If init fails or throws, scan still runs. Prefer try/await with error handling.

6. Die removal race in asyncConvertToDie
   - Removing non-virtual dice if not present in the latest scan map while iterating over a copy is fine, but rapid scan updates could thrash. Consider debounce or authoritative connection state from BLE repo callbacks.

7. Disconnect flows may rely on later pruning
   - disconnectDie for physical dice defers actual removal to asyncConvertToDie; UI may briefly show stale entries. Consider optimistic removal with reconciling on stream.

8. Missing cancellation for device stream listener
   - RollDomain subscribes to DieDomain stream but does not expose dispose() to cancel _deviceStreamListener.

9. Timer.periodic spam without listeners
   - RollDomain posts RollStatus.rolling every 50ms regardless of subscribers. Consider pausing when no listeners or using onListen/onCancel hooks.

10. Web/Platform branches with duplicated logic
   - DI’s platform branches for HA repo are identical; simplify to reduce maintenance risk. Same for BLE else branches.

11. Error handling and null safety in HA integration
   - blinkEntity uses firstOrNull on haEntityTargets; if null, behavior depends on repo. Ensure safeguards and user feedback for missing targets.

12. UI assumptions
   - roll_feathers_app.dart uses ListenableBuilder child as home → fine, but a missing widget update could cause stale tree if main screen depends on VM changes not captured via child.

## Suggested Improvements (near-term)

- Correctness and stability
  - Fix switch in DieDomain.blink with explicit case blocks/returns
  - Close StreamControllers and add dispose methods for domains
  - Await RollDomain.init() during create()
  - Guard ApiDomainServer.getIpAddresses for empty addresses
  - Add error handling around BLE init/scan; expose status to UI
  - Debounce device removal or rely on BLE disconnect events

- UX and features
  - Surface connection status, battery level, and per-die info in UI
  - Allow per-die blink color and HA entity mapping in settings
  - Add manual roll trigger and “lock die” (ignore) toggles
  - Rule editor enhancements: validation, examples, syntax help
  - Display the API server addresses/port in settings with copy button

- Platform parity
  - Document feature limitations per platform (Web: no API server)
  - Explore Linux support if feasible with current BLE lib

- Observability
  - Centralized logger UI page with log level control
  - Basic crash/error reporting toggle (opt‑in)

- Performance
  - Reduce RollStatus.rolling emission frequency or make adaptive
  - Avoid work when no listeners are subscribed

- Testing
  - Add tests for DieDomain (add/remove devices, virtual dice, blink)
  - Add RollDomain end‑to‑end tests (multi‑die roll lifecycle)
  - Add ApiDomainServer test for /api/last-roll and IP enumeration
  - Add HA repository/service unit tests with mock HTTP

## Proposed Roadmap

Milestone 1 — Stabilization (Core fixes) [1–2 weeks]
- Fix DieDomain.blink switch; add unit tests
- Close StreamControllers; add dispose() to RollDomain and ensure DI wires disposals
- Await RollDomain.init() in create(); add startup test
- Harden ApiDomainServer.getIpAddresses and add tests

Milestone 2 — UX/Observability [1–2 weeks]
- Expose connection/battery status and per-die details in UI
- Settings for per-die blink color and HA entity target
- Show API addresses/port; copy to clipboard
- Add in-app log viewer with filtering

Milestone 3 — Integrations and Rules [2 weeks]
- Rule editor validation and example templates
- Better error toasts for HA/API failures; retry/backoff
- Debounce/removal strategy for disconnected dice

Milestone 4 — Testing and Platform Polish [1–2 weeks]
- Expand unit/integration tests across domains and repos
- CI: run flutter analyze and tests on PRs
- Platform docs and feature matrix; investigate Linux

## Acceptance Criteria (per milestone)

- M1: No analyzer errors; DieDomain.blink behaves per-die type; resources disposed cleanly; /api/last-roll stable and IPs listed without crashes; tests added for fixes pass.
- M2: UI shows device states and battery; user can set blink colors and HA targets per die; API addresses visible; basic log viewer working.
- M3: Rule scripts validated with helpful errors; HA/API failures surfaced; device removal less jittery during scans.
- M4: >80% coverage on core domains; CI green on analyze/test; platform notes updated; decision on Linux feasibility.

## Notes/Questions

- Confirm desired behavior for virtual dice when physical dice roll (current auto-simulate). Should virtual dice roll only when selected?
- Should API expose more endpoints (e.g., roll history, connected devices)?
- Any privacy constraints for logging or HA integration that require opt‑in prompts?
