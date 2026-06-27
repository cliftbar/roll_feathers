# Architecture

The app is a layered (onion / ports-and-adapters) design with a strict,
one-directional dependency rule. This document is the reference for where code
belongs and how the layers may depend on each other.

## Layers

```
UI                 driving layer — widgets/screens. Talks to Domains ONLY.
 ↓
DOMAIN             all business logic + orchestration. Owns app state, streams,
 │                 and the "when/why" (e.g. deciding to save settings).
 ├───────────────┬────────────────┐
 ▼               ▼          (siblings — neither calls the other)
SERVICES         REPOSITORIES
wrap external    wrap data /
systems:         persistence:
HA, dddice,      settings, profiles
the die (SDK)
 ↓               ↓
external APIs / dice SDK / BLE    SharedPreferences / storage
```

Below everything sits `core/` (models + ports/interfaces) — a dependency leaf
referenced by every layer. `di/` is the composition root that constructs and
wires concrete implementations. `testing/` holds adapter doubles (noops,
simulators) injected by DI for tests.

## The rules

| Layer | May depend on | Never depends on |
|---|---|---|
| **UI** | Domains | Services, Repositories, SDKs |
| **Domain** | Services, Repositories, core (models/ports) | UI |
| **Service** | external systems (via SDK/API), core | Domains, UI, **Repositories** |
| **Repository** | data stores, core | Domains, UI, **Services** |
| **core** | nothing | everything (it is the leaf) |

Dependencies point **down only**. Services and Repositories are **siblings** —
there is no `service → repository` chain. If a "service" turns out to be a pure
pass-through to a repository, it has no reason to exist; fold it away.

## What each layer is

### UI (`lib/ui/`)
Screens, widgets, view-models. No business logic, no persistence, no transport.
Reaches exactly one layer: the Domain. Gets its domain(s) via DI. Internally the
UI follows MVVM + Command — see below.

#### UI architecture: MVVM + Command

The UI uses Flutter's official app-architecture pattern (`util/command.dart` is
the flutter/website sample). Three roles:

- **View** — a `StatefulWidget` with a `static create(...)` factory that builds
  its ViewModel. `build()` wraps content in
  `ListenableBuilder(listenable: viewModel, …)` and rebuilds on notify. Holds no
  business logic — only layout, ephemeral form state (text controllers), and
  navigation; dispatches user actions to commands.
- **ViewModel** (`*_vm.dart`) — extends `ChangeNotifier`. Holds the screen's
  state, exposes `Command`s, subscribes to domain streams, and calls
  `notifyListeners()`. The bridge from View to Domain.
- **Command0..4** (`util/command.dart`) — wraps one async action; exposes
  `running` / `error` / `completed` / `result` (a `Result<T>`) and is
  single-flight (can't relaunch until it finishes). Views bind buttons to
  `command.execute(...)` and drive spinners/disabled state from `running`.

Data flow:

```
user action → command.execute(args) → ViewModel calls a Domain method
            → updates state + notifyListeners() → ListenableBuilder rebuilds
domain stream → ViewModel subscription → notifyListeners() → rebuild
```

Success text and per-item progress (which Commands don't model) live in plain
VM fields (e.g. `statusMessage`, `transferringId`).

### Domain (`lib/domains/`)
The application core. Holds business logic and orchestration, owns live app
state, and exposes streams/methods the UI consumes. The domain decides *when and
why* — e.g. "on roll, evaluate rules then fire effects," or "save these
settings." It composes Services and Repositories (their interfaces) to do the
*how*.

### Service (`lib/services/`) — wraps an **external system**
An adapter to something outside the app: a third-party API, a device, an SDK.
Its job is to translate that external system into app-standard types and hide its
protocol. Contains **no business logic** — just integration. Examples: Home
Assistant client, dddice client, the die (its SDK is external — we just happen to
have written it).

### Repository (`lib/repositories/`) — wraps a **data store**
The canonical Repository pattern (Fowler / Evans): abstracts persistence and
presents an in-memory-collection view of app data. Translates the store into
app-standard models. **No business logic** — load/save/query only. Examples:
settings store, Pixels profile store.

### core (`lib/core/`, target) — models + ports
Plain value types (profiles, animations, messages, `Blinker`) and the interfaces
(ports) that adapters implement (e.g. the BLE transport contract). Depends on
nothing, so every layer can reference it without creating cycles.

## Pluggability comes from interfaces + DI — not from extra tiers

The ability to "swap a service in easily" comes from the Domain depending on an
**interface** and DI injecting the concrete implementation (this is how
`BleRepository`/`HaService` and their noop doubles already work). You never need
an extra layer for pluggability — so collapsing a logic-less pass-through tier
costs nothing.

## Mapping to DDD vocabulary

DDD splits "service" three ways; this app distributes them deliberately:

| DDD term | Its job | Where it lives here |
|---|---|---|
| **Application Service** | orchestrate use-cases, hold the workflow | **Domain** |
| **Domain Service** | domain logic that doesn't fit an entity | **Domain** |
| **Infrastructure Service** | wrap external systems / SDKs | **Service** |

So our "Domain" absorbs DDD's application + domain services (the orchestration
role), and our "Service" is strictly the **infrastructure** flavor. Our
"Repository" is the textbook Repository pattern. This is standard usage — the
naming distinction is kept because *Repository* is precise and constraining
*Service* to "wraps an external system" makes an otherwise-overloaded word carry
a clear signal (our data vs. someone else's system; local vs. can-time-out).

## Reference example

The **Pixels profile/animation feature** has been migrated to follow these rules
end-to-end and is the worked example to copy:

- UI (`ui/pixels/`) → `PixelProfileDomain` only.
- Domain (`domains/pixel_profile_domain.dart`) → `PixelProfileRepository` (data)
  + `PixelDieService` (external system), siblings, injected via DI.
- Repository: `repositories/pixels/pixel_profile_repository.dart` (interface +
  `SharedPrefs…` impl). Service: `services/pixels/pixel_die_service.dart`.
- Pure logic: `core/pixels/animation_import.dart`.
- App-scoped domain (in `DiWrapper`) + a per-die `PixelDieService` passed into
  die-bound methods.
- UI: `PixelsProfilesScreen` / `PixelsProfileEditorScreen` follow MVVM + Command
  (`*_vm.dart` ViewModels), taking their specific deps (domain + per-die service)
  rather than `DiWrapper`.

## Known divergences (to migrate toward the rules)

The codebase predates this document; these are the gaps to close over time:

- **UI → Service leaks** — several screens still import `services/` directly
  (`app_service`, `dddice_config_service`, `ha_config_service`). Should route
  through a domain, the way `ui/pixels/` now routes through `PixelProfileDomain`.
- **Domain → Repository directness** — e.g. `DieDomain(bleRepo, haRepository,
  …)` takes repositories/transports directly; fine under "domain may use
  repositories," but the BLE/die path needs a clear service/repository split.
- **Dice SDK classification** — `dice_sdks/` is an *external* dependency (a
  vendor SDK we authored). Its app-facing wrapper is a **Service** (done for the
  die: `PixelDieService`); the SDK itself should be treated as external, with
  `core/` owning the shared model/port types. The animation/profile *models*
  still live in `dice_sdks/` (so `core/pixels/animation_import.dart` imports them
  transitionally — see its header); relocating the pure models to `core/` is the
  remaining step.
- **`AppRepository(appService)`** — a repository depending on a service inverts
  the sibling rule; reclassify to match its real role.
- **Home Assistant appears as both a repository and a service** — clarify:
  repository = HTTP transport, service = the app-facing operations on top.
- **ViewModels depend on the whole `DiWrapper`** — `die_screen` / `app_settings`
  VMs take the entire DI container and reach into it, rather than receiving the
  specific domains they need (the way the `pixels/` VMs do). Tighten over time.
