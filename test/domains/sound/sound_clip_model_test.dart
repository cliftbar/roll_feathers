import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/sound/sound_clip.dart';
import 'package:roll_feathers/domains/sound/sound_settings.dart';

void main() {
  // ── SoundClip ──────────────────────────────────────────────────────────────
  group('SoundClip model', () {
    test('1.1 filename is id.extension', () {
      final clip = SoundClip(id: 'abc', name: 'victory', extension: 'mp3');
      expect(clip.filename, equals('abc.mp3'));
    });

    test('1.2 toJson includes id, name, extension', () {
      final clip = SoundClip(id: 'abc', name: 'victory', extension: 'mp3');
      final j = clip.toJson();
      expect(j['id'], equals('abc'));
      expect(j['name'], equals('victory'));
      expect(j['extension'], equals('mp3'));
    });

    test('1.3 fromJson round-trip', () {
      final clip = SoundClip(id: 'x1', name: 'hit', extension: 'wav');
      final rt = SoundClip.fromJson(clip.toJson());
      expect(rt.id, equals(clip.id));
      expect(rt.name, equals(clip.name));
      expect(rt.extension, equals(clip.extension));
    });

    test('1.4 fromJson with extra keys does not crash', () {
      final j = {'id': 'z', 'name': 'test', 'extension': 'ogg', 'extra': 'ignored'};
      expect(() => SoundClip.fromJson(j), returnsNormally);
    });
  });

  // ── SoundSettings ──────────────────────────────────────────────────────────
  group('SoundSettings model', () {
    test('1.5 default values', () {
      final s = SoundSettings();
      expect(s.hardMute, isFalse);
      expect(s.rollingEnabled, isTrue);
      expect(s.rolledEnabled, isTrue);
      expect(s.queueDepth, equals(3));
      expect(s.rollingClipId, isNull);
      expect(s.rolledClipId, isNull);
    });

    test('1.6 toJson includes all set fields', () {
      final s = SoundSettings(hardMute: true, rollingEnabled: false, rolledEnabled: false, queueDepth: 5);
      final j = s.toJson();
      expect(j['hardMute'], isTrue);
      expect(j['rollingEnabled'], isFalse);
      expect(j['rolledEnabled'], isFalse);
      expect(j['queueDepth'], equals(5));
    });

    test('1.7 toJson omits null clip ids', () {
      final s = SoundSettings();
      final j = s.toJson();
      expect(j.containsKey('rollingClipId'), isFalse);
      expect(j.containsKey('rolledClipId'), isFalse);
    });

    test('1.7b toJson includes clip ids when set', () {
      final s = SoundSettings(rollingClipId: 'rid', rolledClipId: 'eid');
      final j = s.toJson();
      expect(j['rollingClipId'], equals('rid'));
      expect(j['rolledClipId'], equals('eid'));
    });

    test('1.8 fromJson round-trip', () {
      final s = SoundSettings(
        hardMute: true,
        rollingEnabled: false,
        rolledEnabled: false,
        queueDepth: 7,
        rollingClipId: 'r',
        rolledClipId: 'e',
      );
      final rt = SoundSettings.fromJson(s.toJson());
      expect(rt.hardMute, equals(s.hardMute));
      expect(rt.rollingEnabled, equals(s.rollingEnabled));
      expect(rt.rolledEnabled, equals(s.rolledEnabled));
      expect(rt.queueDepth, equals(s.queueDepth));
      expect(rt.rollingClipId, equals(s.rollingClipId));
      expect(rt.rolledClipId, equals(s.rolledClipId));
    });

    test('1.9 fromJson with missing fields uses defaults', () {
      final rt = SoundSettings.fromJson({});
      expect(rt.hardMute, isFalse);
      expect(rt.rollingEnabled, isTrue);
      expect(rt.rolledEnabled, isTrue);
      expect(rt.queueDepth, equals(3));
    });
  });
}
