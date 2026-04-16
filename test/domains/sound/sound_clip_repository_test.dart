import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roll_feathers/domains/sound/sound_clip_repository.dart';
import 'package:roll_feathers/domains/sound/sound_settings.dart';

void main() {
  late Directory tmpDir;
  late SoundClipRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('sound_clip_repo_test_');
    repo = SoundClipRepository(testClipsDir: tmpDir);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  // ── Clips library ──────────────────────────────────────────────────────────
  group('SoundClipRepository — clips', () {
    test('2.1 getClips returns empty list when no data', () async {
      expect(await repo.getClips(), isEmpty);
    });

    test('2.2 importClip adds clip to library', () async {
      final src = File('${tmpDir.path}/source.mp3');
      await src.writeAsBytes([0x00]);
      await repo.importClip(src.path, 'victory');
      expect((await repo.getClips()).length, equals(1));
    });

    test('2.3 importClip copies file to clips dir', () async {
      final src = File('${tmpDir.path}/source.mp3');
      await src.writeAsBytes([0xFF]);
      final clip = await repo.importClip(src.path, 'test');
      final destPath = await repo.pathForClip(clip);
      expect(File(destPath).existsSync(), isTrue);
    });

    test('2.4 importClip extracts extension from source path', () async {
      final src = File('${tmpDir.path}/source.ogg');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'test');
      expect(clip.extension, equals('ogg'));
    });

    test('2.5 importClip handles path with no extension', () async {
      final src = File('${tmpDir.path}/audio');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'test');
      expect(clip.extension, equals('audio'));
    });

    test('2.6 importClip assigns unique ids', () async {
      final src1 = File('${tmpDir.path}/a.mp3');
      final src2 = File('${tmpDir.path}/b.mp3');
      await src1.writeAsBytes([0x00]);
      await src2.writeAsBytes([0x00]);
      final c1 = await repo.importClip(src1.path, 'clip1');
      final c2 = await repo.importClip(src2.path, 'clip2');
      expect(c1.id, isNot(equals(c2.id)));
    });

    test('2.7 findByName returns clip when found (exact)', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      await repo.importClip(src.path, 'Victory');
      final found = await repo.findByName('Victory');
      expect(found, isNotNull);
      expect(found!.name, equals('Victory'));
    });

    test('2.8 findByName is case-insensitive', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      await repo.importClip(src.path, 'Victory');
      expect(await repo.findByName('victory'), isNotNull);
      expect(await repo.findByName('VICTORY'), isNotNull);
    });

    test('2.9 findByName returns null when not found', () async {
      expect(await repo.findByName('missing'), isNull);
    });

    test('2.10 findById returns clip when found', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'test');
      final found = await repo.findById(clip.id);
      expect(found?.id, equals(clip.id));
    });

    test('2.11 findById returns null when not found', () async {
      expect(await repo.findById('fake-id'), isNull);
    });

    test('2.12 renameClip changes name, preserves id and extension', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'original');
      await repo.renameClip(clip.id, 'renamed');
      final updated = await repo.findById(clip.id);
      expect(updated?.name, equals('renamed'));
      expect(updated?.id, equals(clip.id));
      expect(updated?.extension, equals('mp3'));
    });

    test('2.13 renameClip is a no-op when id not found', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      await repo.importClip(src.path, 'original');
      await repo.renameClip('nonexistent-id', 'renamed');
      expect((await repo.getClips()).length, equals(1));
      expect((await repo.getClips()).first.name, equals('original'));
    });

    test('2.14 deleteClip removes from library', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'del');
      await repo.deleteClip(clip.id);
      expect(await repo.getClips(), isEmpty);
    });

    test('2.15 deleteClip deletes the file', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'del');
      final path = await repo.pathForClip(clip);
      await repo.deleteClip(clip.id);
      expect(File(path).existsSync(), isFalse);
    });

    test('2.16 deleteClip is a no-op when id not found', () async {
      await expectLater(repo.deleteClip('fake-id'), completes);
    });

    test('2.17 deleteClip handles already-missing file', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'del');
      final path = await repo.pathForClip(clip);
      // Delete the file manually before calling deleteClip
      await File(path).delete();
      await expectLater(repo.deleteClip(clip.id), completes);
    });

    test('2.20 pathForClip returns path inside clips dir', () async {
      final src = File('${tmpDir.path}/s.mp3');
      await src.writeAsBytes([0x00]);
      final clip = await repo.importClip(src.path, 'test');
      final path = await repo.pathForClip(clip);
      expect(path, endsWith(clip.filename));
    });
  });

  // ── Settings ───────────────────────────────────────────────────────────────
  group('SoundClipRepository — settings', () {
    test('2.18 getSettings returns defaults when no data', () async {
      final s = await repo.getSettings();
      expect(s.hardMute, isFalse);
      expect(s.rollingEnabled, isTrue);
      expect(s.queueDepth, equals(3));
    });

    test('2.19 saveSettings + getSettings round-trip', () async {
      final saved = SoundSettings(
        hardMute: true,
        rollingEnabled: false,
        rolledEnabled: false,
        queueDepth: 5,
        rollingClipId: 'r',
        rolledClipId: 'e',
      );
      await repo.saveSettings(saved);
      final loaded = await repo.getSettings();
      expect(loaded.hardMute, equals(saved.hardMute));
      expect(loaded.rollingEnabled, equals(saved.rollingEnabled));
      expect(loaded.rolledEnabled, equals(saved.rolledEnabled));
      expect(loaded.queueDepth, equals(saved.queueDepth));
      expect(loaded.rollingClipId, equals(saved.rollingClipId));
      expect(loaded.rolledClipId, equals(saved.rolledClipId));
    });
  });
}
