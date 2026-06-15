# dddice Integration Spec

Version: 2026-06-13

---

## Goal

Mirror every physical (and virtual) dice roll to a dddice room so remote players
see a live 3D animation of the result. Roll Feathers owns the roll value —
dddice is purely a display layer. Users configure a room and theme once; every
roll is sent automatically.

---

## API Overview

**Base URL:** `https://dddice.com/api/1.0`

**Auth:** `Authorization: Bearer <token>` on every request.

**Create roll:** `POST /roll`

```json
{
  "room": "<room_slug>",
  "dice": [
    { "type": "d20", "theme": "dddice-bees", "value": 17 },
    { "type": "d6",  "theme": "dddice-bees", "value": 4  }
  ],
  "label": "Sneak Attack",
  "operator": { "k": { "1": [] } },
  "external_id": "<our_roll_uuid>"
}
```

`value` is the predetermined physical result — dddice animates to that exact face.
`theme` is required per-die. `room`, `label`, `operator`, `external_id` are optional.

**List rooms:** `GET /room` → `room[]`, each with `name`, `slug`, `is_public`.

**List user themes (dice box):** `GET /dice-box` → `theme[]` owned by the authenticated user.

**Create guest user:** `POST /user` (no auth required) → returns a user object and
a bearer token. Rate-limited to 3 accounts/min/IP.

---

## Authentication Flows

### Activation Flow (primary — for users with a dddice account)

1. `POST /activate` (no auth) → `{ code, secret }`
2. Display `code` to the user; direct them to `https://dddice.com/activate` to enter it
3. Poll `GET /activate/{code}` with `Authorization: Secret <secret>` every 5 seconds
4. When the user completes activation, the response includes `token` — store as Bearer

### Guest Flow (secondary — zero-friction onboarding)

1. `POST /user` (no auth) → user object + bearer token
2. Store the token; use `dddice-bees` as the hardcoded theme (guests have no dice box)
3. Room picker still works: `GET /room` returns rooms the guest has joined

On 401 during a roll: log a warning, set `needsReauth = true` in config. Surface a
re-auth prompt in settings. No silent retry. Guest users re-authenticate by tapping
"Use guest account" again.

---

## Die Type Mapping

| roll_feathers die type | dddice `type` |
|------------------------|---------------|
| d4                     | `d4`          |
| d6                     | `d6`          |
| d8                     | `d8`          |
| d10                    | `d10`         |
| d00 (percentile tens)  | `d10x`        |
| d12                    | `d12`         |
| d20                    | `d20`         |
| anything else          | `mod`         |

---

## Operator Mapping

| roll_feathers roll type | dddice `operator`        |
|-------------------------|--------------------------|
| normal / rule           | omit                     |
| max (advantage)         | `{ "k": { "1": [] } }`  |
| min (disadvantage)      | `{ "d": { "1": [] } }`  |

---

## Roll Label

When a DSL rule fires and `ruleReturn == true`, send `label: ruleName`.
For unlabelled rolls, omit `label`.

---

## Settings Model

```dart
class DddiceConfig {
  final bool enabled;
  final String token;       // Bearer token (activation or guest)
  final bool isGuest;       // true → use dddice-bees, hide theme picker
  final bool needsReauth;   // true → surface re-auth prompt in settings
  final String roomSlug;    // resolved from room picker; never shown raw
  final String roomName;    // display name for settings UI
  final String themeId;     // theme slug sent per-die; empty when isGuest
  final String themeName;   // display name for settings UI
}
```

Persisted in `SharedPreferences` via `AppService`. Keys:
- `dddice_enabled` (bool)
- `dddice_token` (String)
- `dddice_is_guest` (bool)
- `dddice_needs_reauth` (bool)
- `dddice_room_slug` (String)
- `dddice_room_name` (String)
- `dddice_theme_id` (String)
- `dddice_theme_name` (String)

---

## Architecture

### New files

| File | Responsibility |
|------|----------------|
| `lib/services/dddice_config_service.dart` | Read/write `DddiceConfig` from SharedPreferences |
| `lib/repositories/dddice_repository.dart` | `fireRoll(...)`, `listRooms()`, `listThemes()`, `createGuestUser()`, `createActivationCode()`, `pollActivation(code, secret)` |
| `lib/domains/dddice_domain.dart` | Owns `DddiceConfig`; exposes `onRoll(RollResult, RollType)` called by `RollDomain` after recording |

### Existing files touched

| File | Change |
|------|--------|
| `lib/services/app_service.dart` | Add 8 dddice prefs keys |
| `lib/domains/roll_domain.dart` | Call `_ddiceDomain?.onRoll(result, rollType)` in Phase 3 (side effects) of `_stopRollWithResult` |
| `lib/di/di.dart` | Wire `DddiceConfigService`, `DddiceRepository`, `DddiceDomain` |
| `lib/ui/app_settings/` | Add dddice settings section |

### DI wiring

`DddiceRepository` takes `http.Client` and `DddiceConfigService`.
`DddiceDomain` takes `DddiceRepository` and `DddiceConfigService`.
`RollDomain` takes optional `DddiceDomain` (same pattern as HA).

---

## Roll Construction

```dart
// In DddiceRepository.fireRoll(List<GenericDie> dice, RollResult result, RollType rollType)

final theme = config.isGuest ? 'dddice-bees' : config.themeId;

final mapped = dice.map((d) => {
  'type': _dddiceType(d.dType),
  'theme': theme,
  'value': d.getFaceValueOrElse(),
}).toList();

final body = {
  'room': config.roomSlug,
  'dice': mapped,
  if (result.ruleName.isNotEmpty) 'label': result.ruleName,
  if (rollType != RollType.normal) 'operator': _operator(rollType),
  'external_id': result.timestamp.millisecondsSinceEpoch.toString(),
};

// POST /roll, catch all errors, log warning on failure — never throws
// On 401: set config.needsReauth = true via DddiceConfigService
```

---

## Settings UI

Section in `AppSettingsWidget` (same pattern as HA and Webhooks):

1. **Enable toggle** — gates all outbound calls; disabled when `needsReauth`
2. **Auth section** — one of:
   - *Not authenticated:* "Sign in with dddice" button (starts activation flow: show
     code + polling spinner, completes when token arrives) and "Use guest account"
     button (calls `POST /user`, stores token, sets `isGuest = true`)
   - *Authenticated (guest):* username/guest label + "Sign out" button; re-auth
     prompt if `needsReauth`
   - *Authenticated (full):* username label + "Sign out" button; re-auth prompt if
     `needsReauth`
3. **Room picker** — dropdown populated by `GET /room`; shows room names, stores
   slugs; only visible when authenticated; refresh button re-fetches list
4. **Theme picker** — dropdown populated by `GET /dice-box`; shows theme names,
   stores theme IDs; hidden when `isGuest` (guest always uses `dddice-bees`);
   only visible when authenticated with a non-empty room selected

---

## Error Handling

Same policy as webhooks: catch all errors, `_log.warning`, never surface to the
roll path. A dddice failure must never affect roll recording or other side effects.

On 401 specifically: set `needsReauth = true` via `DddiceConfigService.setNeedsReauth()`.
The next time the settings screen opens it will show the re-auth prompt.

---

## Out of Scope (v1)

- Whisper / GM-only rolls
- Receiving other players' rolls (WebSocket / bidirectional)
- sendLocal / listenLocal
- DSL `dddice` target type (room override per rule)
- Per-die room routing
- Per-die theme override
