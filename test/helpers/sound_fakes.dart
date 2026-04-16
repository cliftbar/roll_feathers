import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/domains/sound/sound_clip.dart';
import 'package:roll_feathers/domains/sound/sound_clip_player.dart';
import 'package:roll_feathers/domains/sound/sound_clip_repository.dart';
import 'package:roll_feathers/domains/sound/sound_settings.dart';

// ── FakeSoundClipRepository ────────────────────────────────────────────────

/// In-memory SoundClipRepository — no SharedPreferences, no path_provider.
class FakeSoundClipRepository extends SoundClipRepository {
  List<SoundClip> clips = [];
  SoundSettings settings = SoundSettings();

  /// Fixed file path returned by pathForClip (set per-test as needed).
  String? fixedPath;

  @override
  Future<List<SoundClip>> getClips() async => clips;

  @override
  Future<SoundClip?> findByName(String name) async =>
      clips.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;

  @override
  Future<SoundClip?> findById(String id) async =>
      clips.where((c) => c.id == id).firstOrNull;

  @override
  Future<SoundSettings> getSettings() async => settings;

  @override
  Future<void> saveSettings(SoundSettings s) async => settings = s;

  @override
  Future<String> pathForClip(SoundClip clip) async =>
      fixedPath ?? '/nonexistent/${clip.filename}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final e in this) return e;
    return null;
  }
}

// ── FakeSoundClipPlayer ────────────────────────────────────────────────────

/// Records calls to enqueueByName and enqueueById — does not actually play.
class FakeSoundClipPlayer extends SoundClipPlayer {
  final List<String> enqueuedByName = [];
  final List<String> enqueuedById = [];

  FakeSoundClipPlayer() : super(FakeSoundClipRepository());

  @override
  Future<void> enqueueByName(String clipName) async => enqueuedByName.add(clipName);

  @override
  Future<void> enqueueById(String clipId) async => enqueuedById.add(clipId);
}

// ── FakeAudioPlayer ────────────────────────────────────────────────────────

/// Minimal AudioPlayer replacement for unit tests.
/// `play()` immediately schedules a ProcessingState.completed emission so
/// _drainQueue's firstWhere completes without real audio platform.
class FakeAudioPlayer extends Fake implements AudioPlayer {
  final List<String> filesPlayed = [];
  int playCount = 0;
  bool _disposed = false;

  final _stateCtrl = StreamController<PlayerState>.broadcast();

  // Track whether to throw on the next setFilePath call (for error-path tests).
  bool throwOnSetFilePath = false;

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    if (throwOnSetFilePath) throw Exception('fake setFilePath error');
    filesPlayed.add(filePath);
    return null;
  }

  @override
  Future<void> play() async {
    playCount++;
    // Schedule completion via event queue (not microtask) so that the drain's
    // await continuation runs first and firstWhere subscribes before the event fires.
    Future.delayed(Duration.zero, () {
      if (!_disposed && !_stateCtrl.isClosed) {
        _stateCtrl.add(PlayerState(false, ProcessingState.completed));
      }
    });
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;

  @override
  Future<void> dispose() async {
    _disposed = true;
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
  }

  // Remaining AudioPlayer members are handled by Fake's noSuchMethod.
}

// ── MockAudioPlayer ────────────────────────────────────────────────────────

/// mocktail-based mock — used where fine-grained stub control is needed.
class MockAudioPlayer extends Mock implements AudioPlayer {}
