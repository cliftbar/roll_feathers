import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

import 'sound_clip_repository.dart';

final Logger _log = Logger('SoundClipPlayer');

class SoundClipPlayer {
  final SoundClipRepository _repo;

  AudioPlayer? _player;
  // Paths of clips waiting to play (not counting the currently playing one).
  final List<String> _pending = [];
  bool _playing = false;

  SoundClipPlayer(this._repo);

  Future<void> init() async {
    // Nothing to pre-init; player created lazily on first use.
  }

  Future<void> enqueueById(String clipId) async {
    final settings = await _repo.getSettings();
    if (settings.hardMute) return;

    final clip = await _repo.findById(clipId);
    if (clip == null) return;

    final path = await _repo.pathForClip(clip);
    if (!File(path).existsSync()) return;

    if (_pending.length >= settings.queueDepth) return; // cap: drop incoming

    _pending.add(path);
    if (!_playing) unawaited(_drainQueue());
  }

  Future<void> enqueueByName(String clipName) async {
    final settings = await _repo.getSettings();
    if (settings.hardMute) return;

    final clip = await _repo.findByName(clipName);
    if (clip == null) return; // silent skip — DSL contract

    await enqueueById(clip.id);
  }

  /// Play a clip immediately, bypassing queue and mute. Used by the UI preview button.
  Future<void> previewClip(String clipId) async {
    final clip = await _repo.findById(clipId);
    if (clip == null) return;
    final path = await _repo.pathForClip(clip);
    if (!File(path).existsSync()) return;
    final preview = AudioPlayer();
    try {
      await preview.setFilePath(path);
      await preview.play();
      await preview.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      );
    } catch (e) {
      _log.warning('[previewClip] error: $e');
    } finally {
      await preview.dispose();
    }
  }

  Future<void> _drainQueue() async {
    if (_playing) return;
    _playing = true;
    _player ??= AudioPlayer();

    while (_pending.isNotEmpty) {
      final path = _pending.removeAt(0);
      try {
        await _player!.setFilePath(path);
        await _player!.play();
        await _player!.playerStateStream.firstWhere(
          (s) => s.processingState == ProcessingState.completed,
        );
      } catch (e) {
        _log.warning('[SoundClipPlayer] playback error: $e');
      }
    }

    _playing = false;
  }

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}
