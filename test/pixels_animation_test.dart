import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

void main() {
  group('PixelColor', () {
    test('round-trips through ByteData', () {
      const c = PixelColor(255, 128, 64);
      final buf = ByteData(3);
      c.writeTo(buf, 0);
      expect(buf.getUint8(0), 255); // r
      expect(buf.getUint8(1), 128); // g
      expect(buf.getUint8(2), 64);  // b
    });

    test('equality and identity in list', () {
      const a = PixelColor(255, 0, 0);
      const b = PixelColor(255, 0, 0);
      const c = PixelColor(0, 255, 0);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('RgbKeyframe', () {
    test('encodes and decodes time and colorIndex', () {
      final kf = RgbKeyframe.make(timeMs: 500, colorIndex: 3);
      // time stored as timeMs/2 in 9 bits, decoded as bits * 2
      expect(kf.timeMs, 500);
      expect(kf.colorIndex, 3);
    });

    test('max values fit in 2 bytes', () {
      final kf = RgbKeyframe.make(timeMs: 1022, colorIndex: 127);
      final buf = ByteData(2);
      kf.writeTo(buf, 0);
      // Should not overflow
      expect(buf.getUint16(0, Endian.little), greaterThan(0));
    });

    test('zero time and zero colorIndex', () {
      final kf = RgbKeyframe.make(timeMs: 0, colorIndex: 0);
      expect(kf.timeMs, 0);
      expect(kf.colorIndex, 0);
    });
  });

  group('SimpleKeyframe', () {
    test('encodes and decodes time and intensity', () {
      final kf = SimpleKeyframe.make(timeMs: 400, intensity: 200);
      expect(kf.timeMs, 400);
      // intensity stored as intensity/2 * 2, so max ±1 rounding
      expect(kf.intensity, closeTo(200, 2));
    });
  });

  group('AnimationBits', () {
    test('addColor deduplicates palette entries', () {
      final bits = AnimationBits();
      final idx0 = bits.addColor(const PixelColor(255, 0, 0));
      final idx1 = bits.addColor(const PixelColor(0, 255, 0));
      final idx2 = bits.addColor(const PixelColor(255, 0, 0)); // duplicate
      expect(idx0, 0);
      expect(idx1, 1);
      expect(idx2, 0); // same as idx0
      expect(bits.palette.length, 2);
    });

    test('palette size is 3 bytes per color, 4-byte aligned', () {
      final bits = AnimationBits();
      bits.addColor(const PixelColor(1, 2, 3));
      bits.addColor(const PixelColor(4, 5, 6));
      // 2 colors * 3 bytes = 6, aligned to 8
      expect(bits.computeByteSize(), 8);
    });

    test('serializes palette with 4-byte alignment padding', () {
      final bits = AnimationBits();
      bits.addColor(const PixelColor(10, 20, 30));
      final size = bits.computeByteSize();
      final buf = ByteData(size);
      bits.writeTo(buf, 0);
      expect(buf.getUint8(0), 10);
      expect(buf.getUint8(1), 20);
      expect(buf.getUint8(2), 30);
      // Byte 3 is padding — not checked
    });
  });

  group('PixelAnimationSimple serialization', () {
    test('serializes to 12 bytes with correct type byte', () {
      final bits = AnimationBits();
      final anim = PixelAnimationSimple(
        durationMs: 500,
        faceMask: kFaceMaskAll,
        color: const PixelColor(255, 0, 0),
        count: 2,
        fade: 64,
      );
      final buf = ByteData(12);
      anim.writeTo(buf, 0, bits);

      expect(buf.getUint8(0), 1); // type = simple
      expect(buf.getUint8(1), 0); // animFlags
      expect(buf.getUint16(2, Endian.little), 500); // duration
      expect(buf.getUint32(4, Endian.little), kFaceMaskAll); // faceMask
      // colorIndex: 0 (first palette entry)
      expect(buf.getUint16(8, Endian.little), 0);
      expect(buf.getUint8(10), 2); // count
      expect(buf.getUint8(11), 64); // fade
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationSimple(
        durationMs: 300,
        color: const PixelColor(0, 128, 255),
        count: 3,
        fade: 0,
      );
      final json = anim.toJson();
      final restored = PixelAnimationSimple.fromJson(json);
      expect(restored.durationMs, 300);
      expect(restored.color, const PixelColor(0, 128, 255));
      expect(restored.count, 3);
    });
  });

  group('PixelAnimationRainbow serialization', () {
    test('serializes to 12 bytes with type=2', () {
      final bits = AnimationBits();
      final anim = PixelAnimationRainbow(durationMs: 1000, intensity: 200, cyclesTimes10: 20);
      final buf = ByteData(12);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 2);
      expect(buf.getUint16(2, Endian.little), 1000);
      expect(buf.getUint8(10), 200);
      expect(buf.getUint8(11), 20);
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationRainbow(durationMs: 500, intensity: 100, cyclesTimes10: 5);
      final restored = PixelAnimationRainbow.fromJson(anim.toJson());
      expect(restored.durationMs, 500);
      expect(restored.intensity, 100);
      expect(restored.cyclesTimes10, 5);
    });
  });

  group('PixelConditionRolled', () {
    test('serializes to 8 bytes with type=9', () {
      final cond = PixelConditionRolled(faceMask: 0x000FFFFF);
      final buf = ByteData(8);
      cond.writeTo(buf, 0);
      expect(buf.getUint8(0), 9); // ConditionType.rolled
      expect(buf.getUint32(4, Endian.little), 0x000FFFFF);
    });

    test('JSON round-trip', () {
      final cond = PixelConditionRolled(faceMask: 0xABCD1234);
      final restored = PixelConditionRolled.fromJson(cond.toJson());
      expect(restored.faceMask, 0xABCD1234);
    });
  });

  group('PixelConditionRolling', () {
    test('serializes to 4 bytes with type=3', () {
      final cond = PixelConditionRolling(repeatPeriodMs: 200);
      final buf = ByteData(4);
      cond.writeTo(buf, 0);
      expect(buf.getUint8(0), 3);
      expect(buf.getUint16(2, Endian.little), 200);
    });
  });

  group('PixelConditionHelloGoodbye', () {
    test('serializes to 4 bytes with type=1', () {
      final cond = PixelConditionHelloGoodbye(flags: 1);
      final buf = ByteData(4);
      cond.writeTo(buf, 0);
      expect(buf.getUint8(0), 1);
      expect(buf.getUint8(1), 1);
    });
  });

  group('PixelActionPlayAnimation', () {
    test('serializes to 4 bytes with type=1', () {
      final action = PixelActionPlayAnimation(animIndex: 2, faceIndex: -1, loopCount: 3);
      final buf = ByteData(4);
      action.writeTo(buf, 0);
      expect(buf.getUint8(0), 1); // ActionType.playAnimation
      expect(buf.getUint8(1), 2); // animIndex
      expect(buf.getInt8(2), -1); // faceIndex (signed)
      expect(buf.getUint8(3), 3); // loopCount
    });

    test('JSON round-trip', () {
      final action = PixelActionPlayAnimation(animIndex: 5, faceIndex: 0, loopCount: 2);
      final restored = PixelActionPlayAnimation.fromJson(action.toJson());
      expect(restored.animIndex, 5);
      expect(restored.loopCount, 2);
    });
  });

  group('PixelDataSet serialization', () {
    PixelProfile _simpleProfile() => PixelProfile(
      id: 'test',
      name: 'Test',
      brightness: 200,
      animations: [
        PixelAnimationSimple(
          durationMs: 500,
          color: const PixelColor(255, 0, 0),
          count: 1,
          fade: 0,
        ),
      ],
      rules: [
        PixelRule(
          condition: PixelConditionRolled(),
          actions: [PixelActionPlayAnimation(animIndex: 0)],
        ),
      ],
    );

    test('toByteArray produces non-empty buffer', () {
      final ds = PixelDataSet(_simpleProfile());
      final bytes = ds.toByteArray();
      expect(bytes.length, greaterThan(0));
    });

    test('toAnimationsByteArray is smaller than full dataset', () {
      final profile = _simpleProfile();
      final ds = PixelDataSet(profile);
      final full = ds.toByteArray();
      final anims = ds.toAnimationsByteArray();
      expect(anims.length, lessThan(full.length));
    });

    test('computeStats reflects animation and condition counts', () {
      final ds = PixelDataSet(_simpleProfile());
      final stats = ds.computeStats();
      expect(stats.animationCount, 1);
      expect(stats.ruleCount, 1);
      expect(stats.conditionCount, 1);
      expect(stats.actionCount, 1);
      expect(stats.brightness, 200);
    });

    test('computeInstantStats includes non-zero hash', () {
      final ds = PixelDataSet(_simpleProfile());
      final stats = ds.computeInstantStats();
      expect(stats.animationCount, 1);
      expect(stats.hash, isNonZero);
    });

    test('two identical profiles produce the same hash', () {
      final p1 = _simpleProfile();
      final p2 = _simpleProfile();
      final h1 = PixelDataSet(p1).computeInstantStats().hash;
      final h2 = PixelDataSet(p2).computeInstantStats().hash;
      expect(h1, h2);
    });

    test('rainbow profile serializes without error', () {
      final profile = PixelProfile(
        id: 'rainbow',
        name: 'Rainbow',
        animations: [PixelAnimationRainbow()],
        rules: [
          PixelRule(
            condition: PixelConditionRolling(),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
        ],
      );
      final ds = PixelDataSet(profile);
      expect(() => ds.toByteArray(), returnsNormally);
    });

    test('multiple animations produce correct palette size in stats', () {
      final profile = PixelProfile(
        id: 'multi',
        name: 'Multi',
        animations: [
          PixelAnimationSimple(color: const PixelColor(255, 0, 0)),
          PixelAnimationSimple(color: const PixelColor(0, 255, 0)),
        ],
        rules: [],
      );
      final stats = PixelDataSet(profile).computeStats();
      expect(stats.animationCount, 2);
      // 2 distinct colors × 3 bytes = 6 bytes palette
      expect(stats.paletteSize, 6);
    });
  });

  group('PixelProfile JSON', () {
    test('round-trips through toJson/fromJson', () {
      final profile = PixelProfile(
        id: 'round-trip',
        name: 'My Profile',
        brightness: 128,
        animations: [PixelAnimationSimple(durationMs: 750, color: const PixelColor(100, 150, 200))],
        rules: [
          PixelRule(
            condition: PixelConditionRolled(faceMask: 0xFF),
            actions: [PixelActionPlayAnimation(animIndex: 0, loopCount: 2)],
          ),
        ],
      );
      final json = profile.toJson();
      final restored = PixelProfile.fromJson(json);
      expect(restored.id, 'round-trip');
      expect(restored.name, 'My Profile');
      expect(restored.brightness, 128);
      expect(restored.animations.length, 1);
      expect(restored.rules.length, 1);
      final anim = restored.animations[0] as PixelAnimationSimple;
      expect(anim.durationMs, 750);
      expect(anim.color, const PixelColor(100, 150, 200));
      final cond = restored.rules[0].condition as PixelConditionRolled;
      expect(cond.faceMask, 0xFF);
    });
  });

  group('Bernstein hash', () {
    test('empty input produces 5381', () {
      expect(pixelsBernsteinHash(Uint8List(0)), 5381);
    });

    test('same bytes same hash', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(pixelsBernsteinHash(a), pixelsBernsteinHash(b));
    });

    test('different bytes different hash', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([3, 2, 1]);
      expect(pixelsBernsteinHash(a), isNot(pixelsBernsteinHash(b)));
    });

    test('stays within 32-bit unsigned', () {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));
      final hash = pixelsBernsteinHash(bytes);
      expect(hash, greaterThanOrEqualTo(0));
      expect(hash, lessThanOrEqualTo(0xFFFFFFFF));
    });
  });
}
