# Roll Targets Phase 2 — Webhook and Soundclip Implementation Spec

Version: 2026-04-15

This spec covers two additions to the DSL rules target system: **webhook targets** (already fully
designed) and **soundclip targets** (new). It is written for an AI implementer with no prior
conversation context.

---

## Table of Contents

1. [Background and Existing Architecture](#background)
2. [Implementation Phases Overview](#phases-overview)
3. [Phase 1 — Webhook Target](#phase-1)
4. [Phase 2 — Soundclip Infrastructure](#phase-2)
5. [Phase 3 — Soundclip DSL Target](#phase-3)
6. [Phase 4 — Global Sounds and Per-Die Opt-Out](#phase-4)
7. [Non-Goals and Future Work](#non-goals)

---

## Background and Existing Architecture <a name="background"></a>

### What "targets" are

In the DSL a rule block ends with one or more `on result [range] <target>` lines. When the
aggregate value of a `use selection` block matches the range, all matching targets for that range
fire. Targets are the *consequences* of a rule matching.

### Key files

| File | Role |
|------|------|
| `lib/domains/roll_parser/result_targets.dart` | `ResultTargetType` enum, parser IIFE, action implementations |
| `lib/domains/roll_parser/parser.dart` | `ParseResult`, `RuleParser`, three evaluator paths |
| `lib/domains/roll_domain.dart` | `RollDomain` — orchestrates roll events, calls rule evaluator |
| `lib/services/app_service.dart` | `AppService` + `DieSettings` — SharedPreferences access layer |
| `lib/ui/app_settings/app_settings_screen.dart` | App-level settings navigation |
| `lib/ui/die_screen/single_die_settings_dialog.dart` | Per-die settings dialog |

### `ResultTargetType` enum (`result_targets.dart:163`)

```dart
enum ResultTargetType {
  rule("rule"),
  webhook("webhook"),   // enum exists, dispatch is a stub
  action("action");
  ...
}
```

`webhook` already has an enum variant but its parser and dispatch cases are stubs (break/no-ops).

### Evaluator paths in `parser.dart`

There are three evaluator paths. All new target dispatch must be added to all three:

| Method | Type | Location |
|--------|------|----------|
| `_evaluateRule` | Sync v1.0 | ~line 424 |
| `_evaluateRuleV11` | Sync v1.1 | ~line 588 |
| `_evaluateRuleV11Async` | Async (primary) | ~line 709 |

The async path is the production path. The sync paths should still get working implementations
(fire-and-forget for anything async, via `.ignore()`).

### `ParseResult` (`parser.dart:33`)

```dart
class ParseResult {
  final int result;
  final Map<String, int> allRolled;
  final Map<String, int> rolledEvaluated;
  final String ruleName;
  final bool ruleReturn;
  final int? modifier;
}
```

### `RollDomain` roll lifecycle (`roll_domain.dart`)

- `_startRolling()` (~line 90): called when the first die transitions to rolling state.
  Clears `_rolledDie`, fires `RollStatus.rollStarted`.
- `_stopRollWithResult()` (~line 111): called when all dice have settled.
  Runs rule evaluation loop, builds `RollResult`.
- `_rolledDie`: `Map<String, GenericDie>` — all dice in the current roll, keyed by `dieId`.

### `DieSettings` and `AppService` (`app_service.dart`)

`DieSettings` is a per-die JSON blob stored in SharedPreferences under key `die_settings_{dieId}`.
New per-die fields are added to `DieSettings` with JSON `fromJson`/`toJson` updates.

App-level settings use top-level string keys on the same SharedPreferences instance.

---

## Implementation Phases Overview <a name="phases-overview"></a>

| Phase | What | Depends on |
|-------|------|-----------|
| 1 | Webhook target — parser + dispatch | Nothing new |
| 2 | Soundclip infrastructure — storage, player, UI | Phase 1 not required; can be parallel |
| 3 | Soundclip DSL target — enum, parser, dispatch | Phase 2 (player must exist) |
| 4 | Global sounds + per-die opt-out | Phase 2 + 3 |

Each phase is independently shippable. Phases 1 and 2 can be implemented in parallel.

---

## Phase 1 — Webhook Target <a name="phase-1"></a>

The complete design for this phase already exists in:

```
docs/specs/dsl_webhook_targets.md
```

Read that document in full before implementing. Summary of what must be done:

### 1.1 `lib/domains/roll_parser/result_targets.dart`

- Add imports: `dart:convert`, `package:http/http.dart as http`
- Add `webhookP` parser inside the `resultTarget` IIFE, after `actionSequenceP`, before `actionP`.
  - Parses: `webhook [GET|POST] <url-to-end-of-line>`
  - If first token after `webhook` is `GET` or `POST` (case-insensitive), consume it as the method.
    Otherwise default to `POST`.
  - Store URL in `ResultTargetFunction.action`, method in `args[0]`.
- Add `fireWebhook({required String url, required String method, required Map<String,dynamic> payload})`
  async function after the existing `sequence` function.
  - `POST`: `http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))`
  - `GET`: `http.get(Uri.replace(queryParameters: {'aggregate': ..., 'rule': ...}))`
  - All errors caught and logged to `_rtLog` at WARNING level. Never throws.

### 1.2 `lib/domains/roll_parser/parser.dart`

Fill the three `case ResultTargetType.webhook: break;` stubs:

**Async path `_evaluateRuleV11Async`** — full payload:
- Before the target loop, pre-scan `block.targets` for other `action`-type targets in the same block
  whose range also matches `aggValue` (call this `coActions`). Exclude webhook entries.
  Strip `$ALL_DICE`/`$RESULT_DICE` tokens from args.
- In the dispatch case: build the full POST payload (see `dsl_webhook_targets.md` for all fields),
  then `await fireWebhook(...)`.

**Sync v1.1 path `_evaluateRuleV11`** — minimal payload, fire-and-forget:
```dart
case ResultTargetType.webhook:
  fireWebhook(
    url: t.targetFunction.action,
    method: t.targetFunction.args.isNotEmpty ? t.targetFunction.args[0] : 'POST',
    payload: {'rule': result.name, 'aggregate': aggValue},
  ).ignore();
  break;
```

**Sync v1.0 path `_evaluateRule`** — same pattern as v1.1.

### 1.3 No other file changes needed

`pubspec.yaml` already has `http` as a dependency. Storage, UI, and rule schema are unchanged.

### 1.4 Manual test rule

```
define Webhook Test for roll *d*

  make selection @ALL

  use selection @ALL
    aggregate over selection sum
    on result [*:*] action blink blue
    on result [*:*] webhook POST https://webhook.site/your-uuid
```

Use https://webhook.site to inspect the live payload.

---

## Phase 2 — Soundclip Infrastructure <a name="phase-2"></a>

This phase creates all the plumbing for soundclip management before any DSL wiring.
Nothing in the existing rule system is touched in this phase.

### 2.1 New dependencies (`pubspec.yaml`)

```yaml
dependencies:
  just_audio: ^0.9.x       # cross-platform audio playback with queue support
  file_picker: ^8.x        # user file selection dialog
  path_provider: ^2.x      # documents directory path (needed for file storage)
```

Verify latest compatible versions on pub.dev. `path_provider` may already be a transitive
dependency — add it explicitly regardless.

### 2.2 Data model — `SoundClip`

Create `lib/domains/sound/sound_clip.dart`:

```dart
class SoundClip {
  final String id;         // UUID — stable identifier used at runtime
  final String name;       // User-facing label — referenced in DSL
  final String extension;  // File extension without dot: "mp3", "wav", "ogg", etc.

  SoundClip({required this.id, required this.name, required this.extension});

  String get filename => '$id.$extension';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'extension': extension};

  factory SoundClip.fromJson(Map<String, dynamic> json) => SoundClip(
    id: json['id'] as String,
    name: json['name'] as String,
    extension: json['extension'] as String,
  );
}
```

### 2.3 Sound settings model — `SoundSettings`

Create `lib/domains/sound/sound_settings.dart`:

```dart
class SoundSettings {
  bool hardMute;             // Blocks ALL audio when true
  bool rollingEnabled;       // Global rolling sound on/off
  bool rolledEnabled;        // Global rolled sound on/off
  int queueDepth;            // Max clips in playback queue (default 3)
  String? rollingClipId;     // ID of clip to play on roll start (null = none)
  String? rolledClipId;      // ID of clip to play on roll settle (null = none)

  SoundSettings({
    this.hardMute = false,
    this.rollingEnabled = true,
    this.rolledEnabled = true,
    this.queueDepth = 3,
    this.rollingClipId,
    this.rolledClipId,
  });

  Map<String, dynamic> toJson() => {
    'hardMute': hardMute,
    'rollingEnabled': rollingEnabled,
    'rolledEnabled': rolledEnabled,
    'queueDepth': queueDepth,
    if (rollingClipId != null) 'rollingClipId': rollingClipId,
    if (rolledClipId != null) 'rolledClipId': rolledClipId,
  };

  factory SoundSettings.fromJson(Map<String, dynamic> json) => SoundSettings(
    hardMute: json['hardMute'] as bool? ?? false,
    rollingEnabled: json['rollingEnabled'] as bool? ?? true,
    rolledEnabled: json['rolledEnabled'] as bool? ?? true,
    queueDepth: json['queueDepth'] as int? ?? 3,
    rollingClipId: json['rollingClipId'] as String?,
    rolledClipId: json['rolledClipId'] as String?,
  );
}
```

### 2.4 `SoundClipRepository`

Create `lib/domains/sound/sound_clip_repository.dart`:

Responsibilities: persist the clip library, resolve clip names to `SoundClip` objects, manage
the files directory.

**SharedPreferences key:** `sound_clips_library`
**Storage format:** JSON-encoded list of `SoundClip.toJson()` objects.
**Sound settings key:** `sound_settings`
**File storage path:** `{documentsDirectory}/sound_clips/{clip.filename}`

```dart
class SoundClipRepository {
  static const _libraryKey = 'sound_clips_library';
  static const _settingsKey = 'sound_settings';

  // Load all clips
  Future<List<SoundClip>> getClips() async { ... }

  // Resolve by name (case-insensitive). Returns null if not found.
  Future<SoundClip?> findByName(String name) async { ... }

  // Resolve by ID. Returns null if not found.
  Future<SoundClip?> findById(String id) async { ... }

  // Import: copies sourcePath to app documents dir, saves to library.
  // Returns the created SoundClip.
  Future<SoundClip> importClip(String sourcePath, String name) async { ... }

  // Rename an existing clip.
  Future<void> renameClip(String id, String newName) async { ... }

  // Delete clip from library and remove file from disk.
  Future<void> deleteClip(String id) async { ... }

  // Returns the full filesystem path for a clip.
  Future<String> pathForClip(SoundClip clip) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/sound_clips/${clip.filename}';
  }

  // Sound settings
  Future<SoundSettings> getSettings() async { ... }
  Future<void> saveSettings(SoundSettings settings) async { ... }
}
```

Implementation notes:
- Generate clip ID with `const Uuid().v4()` (add `uuid` package, or use `DateTime.now().microsecondsSinceEpoch.toString()` as a simpler alternative).
- `importClip`: use `File(sourcePath).copy(destPath)` from `dart:io`.
- Extract extension from source path: `p.extension(sourcePath).replaceFirst('.', '')` using the `path` package (already a transitive dependency, but add explicitly if needed).
- Create the `sound_clips/` subdirectory if it doesn't exist before copying.

### 2.5 `SoundClipPlayer`

Create `lib/domains/sound/sound_clip_player.dart`:

Manages a `just_audio` player with a queue cap. All sound in the app routes through this class.

```dart
class SoundClipPlayer {
  final SoundClipRepository _repo;
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  bool _initialized = false;

  SoundClipPlayer(this._repo);

  Future<void> init() async {
    await _player.setAudioSource(_playlist);
    _player.play();
    _initialized = true;
  }

  /// Enqueue a clip by ID for playback. Silently drops if:
  ///   - hard mute is on
  ///   - clip ID is not found in repository
  ///   - queue is at capacity
  Future<void> enqueueById(String clipId) async {
    final settings = await _repo.getSettings();
    if (settings.hardMute) return;

    final clip = await _repo.findById(clipId);
    if (clip == null) return;

    if (_playlist.length >= settings.queueDepth) return; // queue full, drop

    final path = await _repo.pathForClip(clip);
    if (!File(path).existsSync()) return;

    await _playlist.add(AudioSource.file(path));
  }

  /// Enqueue a clip by user-facing name. Silently skips if name not found.
  Future<void> enqueueByName(String clipName) async {
    final settings = await _repo.getSettings();
    if (settings.hardMute) return;

    final clip = await _repo.findByName(clipName);
    if (clip == null) return; // not found → silent skip (DSL contract)

    await enqueueById(clip.id);
  }

  /// Preview a clip immediately, bypassing queue and mute settings.
  /// Used by the management UI.
  Future<void> previewClip(String clipId) async {
    final clip = await _repo.findById(clipId);
    if (clip == null) return;
    final path = await _repo.pathForClip(clip);
    final preview = AudioPlayer();
    await preview.setFilePath(path);
    await preview.play();
    await preview.dispose();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
```

Implementation notes:
- `ConcatenatingAudioSource` auto-advances through clips; the player needs `play()` called once
  and then just continues as clips are added.
- `_playlist.length` gives the number of sources including the currently playing one. Track
  a separate counter of *pending* (not-yet-started) clips if you want the cap to only count
  unplayed clips. Simpler: cap total playlist length.
- If the player reaches the end of the playlist and stops, ensure it resumes when new clips are
  added. Listen to `_player.processingStateStream` and call `_player.play()` if stopped.

### 2.6 `AppService` additions

Add to `app_service.dart`:

```dart
// Sound clips
static const String soundClipsKey = 'sound_clips_library';
static const String soundSettingsKey = 'sound_settings';
```

These keys are used directly by `SoundClipRepository`. Declare them here for consistency with
existing key management, but `SoundClipRepository` may own the implementation.

### 2.7 DI wiring

`SoundClipRepository` and `SoundClipPlayer` must be initialized at app startup and accessible
via the existing DI system (look at `lib/di/di.dart` for the pattern).

- `SoundClipRepository` is a plain service with no setup beyond creating the documents subdirectory.
- `SoundClipPlayer.init()` must be awaited at startup before any sound can play.
- `RollDomain` needs access to both (see Phase 4). Wire them into `RollDomain.create()`.

### 2.8 Sound Clips management screen

Create `lib/ui/app_settings/sound_clips_screen.dart`.

**Navigation:** Add an entry to `AppSettingsWidget` in `app_settings_screen.dart`, in the same
pattern as the existing "Rule Scripts" entry.

**Screen layout:**

```
Sound Settings
──────────────────────────────────────────
[🔇] Hard Mute                    [toggle]
[▶] Rolling Sound                 [toggle]
    Clip: [none ▼]                         ← tap to pick from library
[▶] Rolled Sound                  [toggle]
    Clip: [none ▼]                         ← tap to pick from library
    Queue Depth: [3]              [stepper or number field]
──────────────────────────────────────────
Sound Clips Library                [+ Add]
──────────────────────────────────────────
  victory.mp3          [▶ preview] [delete]
  thud.wav             [▶ preview] [delete]
  ...
```

**"Add" flow:**
1. `FilePicker.platform.pickFiles(type: FileType.audio)` — returns selected file path.
2. Show a text dialog for the clip name (pre-filled with filename without extension).
3. Call `repo.importClip(path, name)`.
4. Refresh the list.

**Rename:** Tap the clip name to inline-edit or show a rename dialog.

**Delete:** Confirm dialog before `repo.deleteClip(id)`.

**Preview:** `player.previewClip(id)` — bypasses queue and mute.

**Clip picker (for Rolling/Rolled Sound selection):**
Show a bottom sheet or dialog listing all clips in the library with a "None" option at the top.
Selecting a clip saves its `id` to `SoundSettings.rollingClipId` / `rolledClipId`.

---

## Phase 3 — Soundclip DSL Target <a name="phase-3"></a>

Wire the soundclip target into the rules DSL. Requires Phase 2 to be complete.

### 3.1 `ResultTargetType` enum (`result_targets.dart:163`)

Add `soundclip`:

```dart
enum ResultTargetType {
  rule("rule"),
  webhook("webhook"),
  action("action"),
  soundclip("soundclip");    // NEW
  ...
}
```

### 3.2 DSL syntax

```
on result [*:*] soundclip victory
on result [18:20] soundclip critical_hit
```

- Keyword: `soundclip`
- Single argument: clip name (a single word identifier; no quotes, no spaces).
- Clip name is matched case-insensitively at dispatch time against the library.
- If the name is not found in the library at fire time → silent skip. No error, no log.

### 3.3 Parser addition (`result_targets.dart`)

Add `soundclipP` inside the `resultTarget` IIFE, after `webhookP`, before `actionSequenceP`:

```dart
// Soundclip: "soundclip <name>"
final soundclipP = pp.seq3(
  "soundclip".toParser(),
  pp.whitespace().plus(),
  wholeWordParser,
).map3((_, __, name) => ResultTargetFunction(
  rtType: ResultTargetType.soundclip,
  action: name,   // clip name stored in action field
  args: [],
));
choices.add(soundclipP);
```

`wholeWordParser` is already defined in `parser_definitions.dart`. The clip name must be a
single token (no spaces). If users need multi-word names, they should use underscores.

### 3.4 Dispatch — all three evaluator paths

In each evaluator's target dispatch `switch` statement, add:

```dart
case ResultTargetType.soundclip:
  await rd.enqueueSound(t.targetFunction.action);
  break;
```

For sync paths use `rd.enqueueSound(...).ignore()`.

This requires `RollDomain` to expose an `enqueueSound(String clipName)` method (see §3.5).

### 3.5 `RollDomain.enqueueSound()`

Add to `RollDomain`:

```dart
Future<void> enqueueSound(String clipName) async {
  await _soundPlayer.enqueueByName(clipName);
}
```

Where `_soundPlayer` is the `SoundClipPlayer` injected at construction.

### 3.6 `ParseResult` — add `hadSoundclip` flag

In `parser.dart`, add a field to `ParseResult`:

```dart
class ParseResult {
  ...
  final bool hadSoundclip;   // NEW — true if any soundclip target fired during this evaluation

  ParseResult({
    ...
    this.hadSoundclip = false,
  });
}
```

In `_evaluateRuleV11Async`, track whether any soundclip target fired during evaluation and
set `hadSoundclip: true` when constructing the returned `ParseResult`. The two sync paths
can always set `hadSoundclip: false` (they do not fire global sounds anyway).

This flag is consumed in Phase 4 to suppress the global rolled sound.

### 3.7 Grammar impact on script saving

`_parseRule()` in `parser.dart` runs on save to extract the rule name. The grammar must
recognize `soundclip` to avoid failing when saving a rule that uses it. Adding `soundclipP`
to the parser IIFE is sufficient — no separate change needed.

---

## Phase 4 — Global Sounds and Per-Die Opt-Out <a name="phase-4"></a>

Requires Phases 2 and 3. Adds the app-level default sounds and per-die suppression.

### 4.1 Rolling sound — triggered in `RollDomain._startRolling()`

Global rolling sound fires once per roll event start. At the moment `_startRolling()` is called,
`_rolledDie` has just been cleared — we don't yet know which specific dice will be in this roll.

**"Normal dice win" rule for rolling sound:**

At roll start, the triggering die is the one whose rolling callback fired. `_startRolling()` does
not currently receive a die parameter. Change the call site in `rollStreamListener`:

```dart
// existing:
_startRolling();

// change to:
await _startRolling(triggeringDie: die);
```

Add `triggeringDie` parameter to `_startRolling()`. If `triggeringDie.settings.useGlobalSounds`
is true (or if die settings cannot be loaded), fire the global rolling sound.

Loading `DieSettings` requires `AppService`. `RollDomain` already holds `appService` — use it.

**Fire the rolling sound:**

```dart
Future<void> _startRolling({GenericDie? triggeringDie}) async {
  _rolledDie.clear();
  _rollUpdateTimer?.cancel();
  _isRolling = true;
  _rollStatusStream.add(RollStatus.rollStarted);
  _rollUpdateTimer = Timer.periodic(...);

  // Global rolling sound
  await _fireGlobalRollingSound(triggeringDie);
}

Future<void> _fireGlobalRollingSound(GenericDie? die) async {
  final settings = await _soundRepo.getSettings();
  if (settings.hardMute || !settings.rollingEnabled || settings.rollingClipId == null) return;

  // Check per-die opt-out. If die has useGlobalSounds = false, suppress.
  if (die != null) {
    final dieSettings = await appService.getDieSettings(die.dieId);
    if (dieSettings != null && !dieSettings.useGlobalSounds) return;
  }

  await _soundPlayer.enqueueById(settings.rollingClipId!);
}
```

`_soundRepo` is the `SoundClipRepository` reference held by `RollDomain`.

### 4.2 Rolled sound — triggered in `RollDomain._stopRollWithResult()`

Global rolled sound fires after rule evaluation completes, **only if no rule soundclip target
fired** (Policy 2).

```dart
Future<int> _stopRollWithResult(...) async {
  ParseResult? ruleResult;
  bool ruleFiredSoundclip = false;

  for (var r in ruleParser.getRules(enabledOnly: true)) {
    ruleResult = await ruleParser.runRuleAsync(r.script, _rolledDie.values.toList());
    if (ruleResult.ruleReturn) {
      rollType = RollType.rule;
      ruleFiredSoundclip = ruleResult.hadSoundclip;
      break;
    }
  }

  // ... existing result-building code ...

  // Global rolled sound — only if no rule soundclip fired
  if (!ruleFiredSoundclip) {
    await _fireGlobalRolledSound();
  }

  return result.rollResult;
}

Future<void> _fireGlobalRolledSound() async {
  final settings = await _soundRepo.getSettings();
  if (settings.hardMute || !settings.rolledEnabled || settings.rolledClipId == null) return;

  // Normal dice win: fire unless ALL dice in the roll have opted out
  bool anyDieWantsSound = false;
  for (final die in _rolledDie.values) {
    final dieSettings = await appService.getDieSettings(die.dieId);
    if (dieSettings == null || dieSettings.useGlobalSounds) {
      anyDieWantsSound = true;
      break;
    }
  }
  if (!anyDieWantsSound) return;

  await _soundPlayer.enqueueById(settings.rolledClipId!);
}
```

### 4.3 Per-die opt-out — `DieSettings`

Add `useGlobalSounds` to `DieSettings` in `app_service.dart`:

```dart
class DieSettings {
  ...
  bool useGlobalSounds;   // NEW — default true

  DieSettings({
    ...
    this.useGlobalSounds = true,
  });

  Map<String, dynamic> toJson() => {
    ...
    'useGlobalSounds': useGlobalSounds,   // add to toJson
  };

  factory DieSettings.fromJson(Map<String, dynamic> json) {
    return DieSettings(
      ...
      useGlobalSounds: json['useGlobalSounds'] as bool? ?? true,   // add to fromJson
    );
  }
}
```

Default `true` ensures backward compatibility: existing die settings without this key continue
to participate in global sounds.

### 4.4 Per-die settings UI (`single_die_settings_dialog.dart`)

Add a toggle to the die settings dialog:

```
[🔊] Use global sound effects    [toggle]
```

- Reads from `DieSettings.useGlobalSounds`
- Saves via `appService.saveDieSettings(dieId, settings)`
- Place it near the other sound/visual settings (rolling flash section)

---

## Summary of all changed/created files

### Phase 1

| File | Change |
|------|--------|
| `lib/domains/roll_parser/result_targets.dart` | Add `webhookP` parser, add `fireWebhook()` function |
| `lib/domains/roll_parser/parser.dart` | Fill 3 webhook dispatch stubs |

### Phase 2

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `just_audio`, `file_picker`, `path_provider` |
| `lib/domains/sound/sound_clip.dart` | **NEW** — `SoundClip` model |
| `lib/domains/sound/sound_settings.dart` | **NEW** — `SoundSettings` model |
| `lib/domains/sound/sound_clip_repository.dart` | **NEW** — library storage + file management |
| `lib/domains/sound/sound_clip_player.dart` | **NEW** — `just_audio` wrapper with queue |
| `lib/di/di.dart` | Wire `SoundClipRepository` and `SoundClipPlayer` |
| `lib/services/app_service.dart` | Add key constants |
| `lib/ui/app_settings/sound_clips_screen.dart` | **NEW** — management + settings screen |
| `lib/ui/app_settings/app_settings_screen.dart` | Add navigation entry to sound clips screen |

### Phase 3

| File | Change |
|------|--------|
| `lib/domains/roll_parser/result_targets.dart` | Add `soundclip` to enum, add `soundclipP` parser |
| `lib/domains/roll_parser/parser.dart` | Add `hadSoundclip` to `ParseResult`; fill 3 soundclip dispatch stubs; track `hadSoundclip` in async evaluator |
| `lib/domains/roll_domain.dart` | Add `enqueueSound()` method; hold `SoundClipPlayer` reference |

### Phase 4

| File | Change |
|------|--------|
| `lib/domains/roll_domain.dart` | Add `_fireGlobalRollingSound()`, `_fireGlobalRolledSound()`; update `_startRolling()` signature; update `_stopRollWithResult()` |
| `lib/services/app_service.dart` | Add `useGlobalSounds` to `DieSettings` |
| `lib/ui/die_screen/single_die_settings_dialog.dart` | Add "Use global sound effects" toggle |

---

## Non-Goals and Future Work <a name="non-goals"></a>

The following are explicitly out of scope for this implementation. Do not add them now.

- **Volume per soundclip target** — `on result [*:*] soundclip victory volume 0.8`
- **Loop count** — `on result [*:*] soundclip victory loop 3`
- **Die-identity DSL filter** — `with die "Red Pixel"` transform for targeting specific dice in rules
- **Palette and gradient actions** — separate spec at `docs/dsl/future_additions_spec.md`
- **Soundclip names with spaces** — names with underscores are sufficient for now
- **Multiple global rolling/rolled clips** — one clip per slot only
- **Audio ducking or cross-fade** — clips play sequentially, no mixing
