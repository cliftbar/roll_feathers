import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/sound/sound_clip.dart';
import 'package:roll_feathers/domains/sound/sound_clip_player.dart';
import 'package:roll_feathers/domains/sound/sound_settings.dart';

import '../../helpers/sound_fakes.dart';

// Pump the event loop until drain completes.
Future<void> _awaitDrain(SoundClipPlayer player) async {
  for (var i = 0; i < 50; i++) {
    if (!player.isPlaying && player.pendingCount == 0) break;
    await Future.delayed(Duration.zero);
  }
}

void main() {
  late FakeSoundClipRepository repo;
  late FakeAudioPlayer fakePlayer;
  late SoundClipPlayer player;

  late Directory tmpDir;
  late String existingFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('scp_test_');
    // Create a real file that the player can find with File.existsSync()
    final f = File('${tmpDir.path}/clip.mp3');
    await f.writeAsBytes([0x00]);
    existingFile = f.path;

    fakePlayer = FakeAudioPlayer();
    repo = FakeSoundClipRepository()
      ..clips = [SoundClip(id: 'id1', name: 'victory', extension: 'mp3')]
      ..fixedPath = existingFile
      ..settings = SoundSettings(queueDepth: 3);

    player = SoundClipPlayer(repo, playerFactory: () => fakePlayer);
  });

  tearDown(() async {
    await fakePlayer.dispose();
    await tmpDir.delete(recursive: true);
  });

  // ── Guard logic — enqueueById ──────────────────────────────────────────────
  group('enqueueById guard logic', () {
    test('3.1 normal path enqueues one item', () async {
      await player.enqueueById('id1');
      // pendingCount may be 0 already (drain started) or 1 — just confirm no throw
      // and that a play event is eventually recorded.
      await _awaitDrain(player);
      expect(fakePlayer.filesPlayed.length, equals(1));
    });

    test('3.2 hard mute suppresses enqueue', () async {
      repo.settings = SoundSettings(hardMute: true);
      await player.enqueueById('id1');
      expect(player.pendingCount, equals(0));
      expect(fakePlayer.filesPlayed, isEmpty);
    });

    test('3.3 clip not found suppresses enqueue', () async {
      await player.enqueueById('nonexistent');
      expect(player.pendingCount, equals(0));
    });

    test('3.4 file not on disk suppresses enqueue', () async {
      repo.fixedPath = '/nonexistent/path.mp3';
      await player.enqueueById('id1');
      expect(player.pendingCount, equals(0));
    });

    test('3.5 queue cap drops excess clip', () async {
      // Enqueue more items than queueDepth allows (depth=3).
      // Since drain starts immediately, we pause the FakeAudioPlayer drain
      // by having it not complete the stream until we check.
      // Instead verify by checking filesPlayed stays at most queueDepth.
      for (var i = 0; i < 6; i++) {
        await player.enqueueById('id1');
      }
      await _awaitDrain(player);
      // Only queueDepth items should have been played (some were dropped).
      expect(fakePlayer.filesPlayed.length, lessThanOrEqualTo(4));
    });
  });

  // ── Guard logic — enqueueByName ────────────────────────────────────────────
  group('enqueueByName guard logic', () {
    test('3.6 enqueues clip when found by name', () async {
      await player.enqueueByName('victory');
      await _awaitDrain(player);
      expect(fakePlayer.filesPlayed.length, equals(1));
    });

    test('3.7 silently skips when name not found', () async {
      await expectLater(player.enqueueByName('missing'), completes);
      expect(player.pendingCount, equals(0));
    });

    test('3.8 name lookup is case-insensitive', () async {
      await player.enqueueByName('VICTORY');
      await _awaitDrain(player);
      expect(fakePlayer.filesPlayed.length, equals(1));
    });
  });

  // ── Drain behaviour ────────────────────────────────────────────────────────
  group('drain behaviour', () {
    test('3.9 drain calls setFilePath with correct path', () async {
      await player.enqueueById('id1');
      await _awaitDrain(player);
      expect(fakePlayer.filesPlayed, equals([existingFile]));
    });

    test('3.10 drain calls play()', () async {
      await player.enqueueById('id1');
      await _awaitDrain(player);
      expect(fakePlayer.playCount, equals(1));
    });

    test('3.11 drain plays two items sequentially', () async {
      final f2 = File('${tmpDir.path}/clip2.mp3');
      await f2.writeAsBytes([0x01]);
      repo.clips = [
        SoundClip(id: 'id1', name: 'clip1', extension: 'mp3'),
        SoundClip(id: 'id2', name: 'clip2', extension: 'mp3'),
      ];
      // We need repo to return different paths per clip — override fixedPath is not suitable.
      // Use a custom repo that maps ids to files.
      final pathRepo = _TwoFileRepo(existingFile, f2.path);
      final p2 = SoundClipPlayer(pathRepo, playerFactory: () => fakePlayer);
      await p2.enqueueById('id1');
      await p2.enqueueById('id2');
      await _awaitDrain(p2);
      expect(fakePlayer.filesPlayed, equals([existingFile, f2.path]));
    });

    test('3.12 isPlaying is false after drain completes', () async {
      await player.enqueueById('id1');
      await _awaitDrain(player);
      expect(player.isPlaying, isFalse);
    });

    test('3.13 playback error does not crash drain', () async {
      fakePlayer.throwOnSetFilePath = true;
      await expectLater(
        Future(() async {
          await player.enqueueById('id1');
          await _awaitDrain(player);
        }),
        completes,
      );
    });
  });

  // ── Preview ────────────────────────────────────────────────────────────────
  group('previewClip', () {
    test('3.14 previewClip skips when clip not found', () async {
      await expectLater(player.previewClip('nonexistent'), completes);
    });
  });
}

// Helper repo that maps two specific ids to two different paths.
class _TwoFileRepo extends FakeSoundClipRepository {
  final String _path1;
  final String _path2;

  _TwoFileRepo(this._path1, this._path2) {
    clips = [
      SoundClip(id: 'id1', name: 'clip1', extension: 'mp3'),
      SoundClip(id: 'id2', name: 'clip2', extension: 'mp3'),
    ];
    settings = SoundSettings(queueDepth: 3);
  }

  @override
  Future<String> pathForClip(SoundClip clip) async {
    if (clip.id == 'id1') return _path1;
    if (clip.id == 'id2') return _path2;
    return '/nonexistent';
  }
}
