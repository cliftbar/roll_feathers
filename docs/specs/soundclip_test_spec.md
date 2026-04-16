# Soundclip Test Spec

## Overview

Full test coverage for the soundclip feature, covering:

- **Models** — `SoundClip` and `SoundSettings` serialisation
- **Repository** — `SoundClipRepository` CRUD operations and settings persistence
- **Player** — `SoundClipPlayer` guard logic and queue behaviour
- **DSL parsing** — `soundclip <name>` grammar fragment
- **Evaluator dispatch** — `soundclip` target fires `enqueueSound`; `hadSoundclip` flag
- **Global sounds** — `RollDomain` rolling/rolled sound gating and per-die opt-out

---

## Prerequisites: injectable hooks for testability

### `lib/domains/sound/sound_clip_repository.dart`

Add optional `Directory? testClipsDir` to the constructor. When provided, use it directly instead of calling `getApplicationDocumentsDirectory()` (bypasses `path_provider` platform channel in unit tests).

### `lib/domains/sound/sound_clip_player.dart`

1. Add optional `AudioPlayer Function()? playerFactory`. When provided, use it in `_drainQueue()` instead of `AudioPlayer()`.
2. Add `@visibleForTesting int get pendingCount => _pending.length`.
3. Add `@visibleForTesting bool get isPlaying => _playing`.

---

## Test files

```
test/helpers/sound_fakes.dart                        # FakeSoundClipRepository, FakeSoundClipPlayer, FakeAudioPlayer
test/domains/sound/
  sound_clip_model_test.dart                         # SoundClip + SoundSettings model
  sound_clip_repository_test.dart                    # SoundClipRepository CRUD
  sound_clip_player_test.dart                        # SoundClipPlayer guard + queue
test/domains/roll_parser/
  dsl_soundclip_parsing_test.dart                    # DSL grammar fragment
  dsl_soundclip_evaluation_test.dart                 # Evaluator dispatch + hadSoundclip
test/domains/
  roll_domain_global_sounds_test.dart                # RollDomain rolling/rolled gating
```

---

## Suite 1 — Models  (`sound_clip_model_test.dart`)

No platform deps. Pure Dart.

### SoundClip

| # | Test name | Expected |
|---|-----------|----------|
| 1.1 | `filename` is `id.extension` | `SoundClip(id:'abc', name:'x', extension:'mp3').filename == 'abc.mp3'` |
| 1.2 | `toJson` includes id, name, extension | keys present, values match |
| 1.3 | `fromJson` round-trip | `fromJson(clip.toJson()) == same fields` |
| 1.4 | `fromJson` with extra keys does not crash | extra key in map → ignored |

### SoundSettings

| # | Test name | Expected |
|---|-----------|----------|
| 1.5 | default values | `hardMute=false`, `rollingEnabled=true`, `rolledEnabled=true`, `queueDepth=3`, clip ids null |
| 1.6 | `toJson` includes all set fields | keys present |
| 1.7 | `toJson` omits null clip ids | `rollingClipId` absent when null |
| 1.8 | `fromJson` round-trip | same fields after round-trip |
| 1.9 | `fromJson` with missing fields uses defaults | partial JSON → missing fields get defaults |

---

## Suite 2 — Repository  (`sound_clip_repository_test.dart`)

Uses `SharedPreferences.setMockInitialValues({})` + temp directory injected via `testClipsDir`.

| # | Test name | Setup / Expected |
|---|-----------|-----------------|
| 2.1 | `getClips` returns empty list when no data | fresh prefs → `[]` |
| 2.2 | `importClip` adds clip to library | import once → `getClips().length == 1` |
| 2.3 | `importClip` copies file to clips dir | dest file exists after import |
| 2.4 | `importClip` extracts extension from source path | `source.mp3` → `clip.extension == 'mp3'` |
| 2.5 | `importClip` handles path with no extension | no dot in path → `extension == 'audio'` |
| 2.6 | `importClip` assigns unique uuid id | two imports → different ids |
| 2.7 | `findByName` returns clip when found (exact) | imported clip found by name |
| 2.8 | `findByName` is case-insensitive | import "Victory", search "victory" → found |
| 2.9 | `findByName` returns null when not found | search "missing" → null |
| 2.10 | `findById` returns clip when found | search by id → correct clip |
| 2.11 | `findById` returns null when not found | search "fake-id" → null |
| 2.12 | `renameClip` changes name, preserves other fields | rename → name changed, id/extension unchanged |
| 2.13 | `renameClip` is a no-op when id not found | rename non-existent id → library unchanged |
| 2.14 | `deleteClip` removes from library | delete → `getClips().length == 0` |
| 2.15 | `deleteClip` deletes the file | delete → file no longer exists |
| 2.16 | `deleteClip` is a no-op when id not found | delete non-existent id → no error |
| 2.17 | `deleteClip` handles already-missing file | file deleted before `deleteClip` → no error |
| 2.18 | `getSettings` returns defaults when no data | fresh prefs → default SoundSettings |
| 2.19 | `saveSettings` + `getSettings` round-trip | save modified settings → read back same values |
| 2.20 | `pathForClip` returns path inside clips dir | path ends with `clip.filename` |

---

## Suite 3 — Player  (`sound_clip_player_test.dart`)

Uses `FakeSoundClipRepository` + `FakeAudioPlayer` injected via `playerFactory`.

### Guard logic (`enqueueById`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 3.1 | normal path enqueues one item | valid clip + file + normal settings | `pendingCount == 1` after call (before drain completes) |
| 3.2 | hard mute suppresses enqueue | `settings.hardMute = true` | `pendingCount == 0` |
| 3.3 | clip not found suppresses enqueue | clip id not in repo | `pendingCount == 0` |
| 3.4 | file not on disk suppresses enqueue | clip exists in repo but file absent | `pendingCount == 0` |
| 3.5 | queue cap drops excess clip | enqueue `queueDepth + 1` items | `pendingCount <= queueDepth` |

### Guard logic (`enqueueByName`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 3.6 | enqueues clip when found by name | clip with matching name exists | `pendingCount == 1` |
| 3.7 | silently skips when name not found | no matching clip | `pendingCount == 0`, no error thrown |
| 3.8 | name lookup is case-insensitive | clip named "Victory", enqueue "victory" | enqueued |

### Drain behaviour (`_drainQueue` via `FakeAudioPlayer`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 3.9 | drain calls `setFilePath` with correct path | enqueue one item → drain | `FakeAudioPlayer.filesPlayed[0] == expectedPath` |
| 3.10 | drain calls `play()` | enqueue one item → drain | `FakeAudioPlayer.playCount == 1` |
| 3.11 | drain plays items sequentially | enqueue 2 items | `filesPlayed` has both paths in order |
| 3.12 | `_playing` is false after drain completes | drain 1 item | `isPlaying == false` after drain |
| 3.13 | playback error does not crash drain | `FakeAudioPlayer.setFilePath` throws | drain completes normally; subsequent items unaffected |

### Preview

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 3.14 | `previewClip` skips when clip not found | invalid id | no error |

---

## Suite 4 — DSL parsing  (`dsl_soundclip_parsing_test.dart`)

No platform deps. Uses `resultTarget` parser and `v11ScriptParser`.

| # | Test name | Input | Expected |
|---|-----------|-------|----------|
| 4.1 | `soundclip <name>` parses correctly | `"soundclip victory"` | `rtType=soundclip`, `action="victory"`, `args=[]` |
| 4.2 | name with underscores | `"soundclip roll_hit"` | `action="roll_hit"` |
| 4.3 | name with numbers | `"soundclip clip123"` | `action="clip123"` |
| 4.4 | `ResultTargetType.byKey('soundclip')` resolves | | equals `ResultTargetType.soundclip` |
| 4.5 | soundclip in full v11 script | script with `on result [*:*] soundclip victory` | parses successfully, target type is `soundclip` |
| 4.6 | soundclip coexists with action in same block | blink + soundclip in same block | both targets present, correct types |

---

## Suite 5 — Evaluator dispatch  (`dsl_soundclip_evaluation_test.dart`)

Uses `FakeSoundClipPlayer` injected via `RollDomain.create(soundPlayer: fakeSoundPlayer)`.

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 5.1 | soundclip target calls `enqueueByName` when range matches | script with `on result [*:*] soundclip victory`, dice sum > 0 | `enqueuedByName == ["victory"]` |
| 5.2 | soundclip does not fire when range does not match | range `[10:20]`, dice sum=5 | `enqueuedByName` is empty |
| 5.3 | `hadSoundclip` is true when soundclip fired (async path) | matching range | `result.hadSoundclip == true` |
| 5.4 | `hadSoundclip` is false when range does not match | non-matching range | `result.hadSoundclip == false` |
| 5.5 | `hadSoundclip` is false when no soundclip target in script | action-only script | `result.hadSoundclip == false` |
| 5.6 | soundclip silent-skip when player returns without enqueue | enqueueByName does nothing (clip not found) | no error, evaluation completes |
| 5.7 | multiple soundclip targets in same block each fire | two soundclip targets, same range | `enqueuedByName.length == 2` |

---

## Suite 6 — Global sounds  (`roll_domain_global_sounds_test.dart`)

Uses `FakeSoundClipRepository` + `FakeSoundClipPlayer` injected into `RollDomain.create`.
Uses `TestBleDie.fireRollState()` to trigger the roll lifecycle, following the pattern in
`roll_domain_rolling_flash_test.dart`.

### Rolling sound (`_fireGlobalRollingSound`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 6.1 | rolling sound fires when all conditions met | `rollingEnabled=true`, `rollingClipId=<id>`, die fired rolling | `player.enqueuedById` contains clip id |
| 6.2 | rolling sound suppressed by hard mute | `hardMute=true` | `enqueuedById` empty |
| 6.3 | rolling sound suppressed when disabled | `rollingEnabled=false` | `enqueuedById` empty |
| 6.4 | rolling sound suppressed when clip id is null | `rollingClipId=null` | `enqueuedById` empty |
| 6.5 | rolling sound suppressed when die has `useGlobalSounds=false` | die.useGlobalSounds = false | `enqueuedById` empty |
| 6.6 | rolling sound fires when `useGlobalSounds=true` (default) | default die | `enqueuedById` contains clip id |

### Rolled sound (`_fireGlobalRolledSound`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 6.7 | rolled sound fires when all conditions met | `rolledEnabled=true`, `rolledClipId=<id>`, die fires rolled | `enqueuedById` contains rolled clip id |
| 6.8 | rolled sound suppressed by hard mute | `hardMute=true` | `enqueuedById` empty (after rolled) |
| 6.9 | rolled sound suppressed when disabled | `rolledEnabled=false` | `enqueuedById` empty |
| 6.10 | rolled sound suppressed when clip id is null | `rolledClipId=null` | `enqueuedById` empty |
| 6.11 | rolled sound suppressed when all dice opted out | all dice `useGlobalSounds=false` | `enqueuedById` empty |
| 6.12 | rolled sound fires when at least one die has `useGlobalSounds=true` | two dice, one opts out | `enqueuedById` contains clip id |
| 6.13 | rolled sound fires when `_rolledDie` is empty (virtual-only) | no BLE dice, virtual only | `enqueuedById` contains clip id |

### Soundclip rule suppression

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 6.14 | rule soundclip suppresses global rolled sound | rule with `soundclip` target fires | `enqueuedById` does NOT contain rolledClipId |
| 6.15 | visual-only rule does NOT suppress global rolled sound | rule with `action blink` only | rolled sound still fires |

---

## Notes

- `SharedPreferences.setMockInitialValues({})` resets in-memory prefs. Call in `setUp` to isolate each repo test.
- `FakeAudioPlayer` uses `Future.microtask` to emit `ProcessingState.completed` after `play()`, so drain completes within a few microtask ticks. Await with `while (player.isPlaying) await Future.delayed(Duration.zero)` after enqueue.
- `TestBleDie` and `RecordingDieDomain` from `lib/testing/dsl_test_harness.dart` are already used by rolling flash tests — reuse the same pattern here.
- `FakeSoundClipPlayer` for evaluator/global sound tests only needs to record calls; it does not need a real AudioPlayer.
