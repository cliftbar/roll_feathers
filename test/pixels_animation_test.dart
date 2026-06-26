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
      // Use values that remain distinct after gamma-3.0 correction:
      // gamma(200)=123, gamma(150)=52, so (200,0,0) → (123,0,0) and (0,200,0) → (0,123,0)
      bits.addColor(const PixelColor(200, 0, 0));
      bits.addColor(const PixelColor(0, 200, 0));
      // 2 colors * 3 bytes = 6, aligned to 8
      expect(bits.computeByteSize(), 8);
    });

    test('serializes palette with 4-byte alignment padding', () {
      final bits = AnimationBits();
      // gamma(255)=255 so a pure-red (255,0,0) stores as (255,0,0) after correction
      bits.addColor(const PixelColor(255, 0, 0));
      final size = bits.computeByteSize();
      final buf = ByteData(size);
      bits.writeTo(buf, 0);
      expect(buf.getUint8(0), 255);
      expect(buf.getUint8(1), 0);
      expect(buf.getUint8(2), 0);
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

  group('PixelConditionHandling', () {
    test('serializes to 4 bytes (type + 3 padding) with type=2', () {
      final cond = PixelConditionHandling();
      expect(cond.byteSize, 4);
      final buf = ByteData(4);
      cond.writeTo(buf, 0);
      expect(buf.getUint8(0), 2);
      expect(buf.getUint32(0, Endian.little), 2); // padding bytes are zero
    });
  });

  group('PixelConditionCrooked', () {
    test('serializes to 4 bytes (type + 3 padding) with type=5', () {
      final cond = PixelConditionCrooked();
      expect(cond.byteSize, 4);
      final buf = ByteData(4);
      cond.writeTo(buf, 0);
      expect(buf.getUint8(0), 5);
      expect(buf.getUint32(0, Endian.little), 5);
    });
  });

  group('PixelConditionIdle', () {
    test('serializes to 4 bytes with type=8 and repeatPeriodMs', () {
      final cond = PixelConditionIdle(repeatPeriodMs: 5000);
      expect(cond.byteSize, 4);
      final buf = ByteData(4);
      cond.writeTo(buf, 0);
      expect(buf.getUint8(0), 8);
      expect(buf.getUint16(2, Endian.little), 5000);
    });

    test('JSON round-trip', () {
      final restored = PixelConditionIdle.fromJson(
        PixelConditionIdle(repeatPeriodMs: 1234).toJson());
      expect(restored.repeatPeriodMs, 1234);
    });
  });

  group('PixelAnimationBlinkId', () {
    test('serializes to 6 bytes with type=8', () {
      final bits = AnimationBits();
      final anim = PixelAnimationBlinkId(durationMs: 1000, framesPerBlink: 6, brightness: 200);
      expect(anim.byteSize, 6);
      final buf = ByteData(6);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 8); // AnimationType.blinkId
      expect(buf.getUint16(2, Endian.little), 1000);
      expect(buf.getUint8(4), 6); // framesPerBlink
      expect(buf.getUint8(5), 200); // brightness
    });

    test('JSON round-trip', () {
      final restored = PixelAnimationBlinkId.fromJson(
        PixelAnimationBlinkId(durationMs: 800, framesPerBlink: 4, brightness: 128).toJson());
      expect(restored.durationMs, 800);
      expect(restored.framesPerBlink, 4);
      expect(restored.brightness, 128);
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

  group('PixelGradient', () {
    test('addToBits adds correct number of keyframes', () {
      final bits = AnimationBits();
      final grad = PixelGradient.twoColor(const PixelColor(255, 0, 0), const PixelColor(0, 0, 255));
      final trackIdx = grad.addToBits(bits);
      expect(trackIdx, 0);
      expect(bits.rgbKeyframes.length, 3); // start, mid, end
      expect(bits.rgbTracks.length, 1);
    });

    test('solid gradient adds 2 keyframes', () {
      final bits = AnimationBits();
      final trackIdx = PixelGradient.solid(const PixelColor(0, 255, 0)).addToBits(bits);
      expect(trackIdx, 0);
      expect(bits.rgbKeyframes.length, 2);
    });

    test('JSON round-trip preserves keyframes', () {
      final grad = PixelGradient.rainbow;
      final json = grad.toJson();
      final restored = PixelGradient.fromJson(json);
      expect(restored.keyframes.length, grad.keyframes.length);
      expect(restored.keyframes.first.$1, grad.keyframes.first.$1);
    });
  });

  group('PixelAnimationGradient', () {
    test('byteSize is 12', () {
      expect(PixelAnimationGradient().byteSize, 12);
    });

    test('type is gradient (5)', () {
      expect(PixelAnimationGradient().type, PixelAnimationType.gradient);
    });

    test('serializes without error', () {
      final profile = PixelProfile(
        id: 'g', name: 'Gradient', animations: [PixelAnimationGradient()],
        rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
      );
      expect(() => PixelDataSet(profile).toByteArray(), returnsNormally);
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationGradient(durationMs: 1500, gradient: PixelGradient.water);
      final restored = PixelAnimationGradient.fromJson(anim.toJson());
      expect(restored.durationMs, 1500);
      expect(restored.gradient.keyframes.length, anim.gradient.keyframes.length);
    });

    test('first byte of serialized data is type 5', () {
      final anim = PixelAnimationGradient();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      final buf = ByteData(12);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 5);
    });
  });

  group('PixelAnimationCycle', () {
    test('byteSize is 14', () {
      expect(PixelAnimationCycle().byteSize, 14);
    });

    test('type is cycle (7)', () {
      expect(PixelAnimationCycle().type, PixelAnimationType.cycle);
    });

    test('first byte of serialized data is type 7', () {
      final anim = PixelAnimationCycle();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      final buf = ByteData(14);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 7);
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationCycle(durationMs: 2500, intensity: 200, cyclesTimes10: 15);
      final restored = PixelAnimationCycle.fromJson(anim.toJson());
      expect(restored.durationMs, 2500);
      expect(restored.intensity, 200);
      expect(restored.cyclesTimes10, 15);
    });
  });

  group('PixelAnimationNoise', () {
    test('byteSize is 18', () {
      expect(PixelAnimationNoise().byteSize, 18);
    });

    test('type is noise (6)', () {
      expect(PixelAnimationNoise().type, PixelAnimationType.noise);
    });

    test('first byte of serialized data is type 6', () {
      final anim = PixelAnimationNoise();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      final buf = ByteData(18);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 6);
    });

    test('adds 2 gradient tracks to bits', () {
      final anim = PixelAnimationNoise();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      expect(bits.rgbTracks.length, 2);
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationNoise(durationMs: 2000, blinkFrequencyTimes1000: 1500);
      final restored = PixelAnimationNoise.fromJson(anim.toJson());
      expect(restored.durationMs, 2000);
      expect(restored.blinkFrequencyTimes1000, 1500);
    });
  });

  group('PixelAnimationNormals', () {
    test('byteSize is 22', () {
      expect(PixelAnimationNormals().byteSize, 22);
    });

    test('type is normals (9)', () {
      expect(PixelAnimationNormals().type, PixelAnimationType.normals);
    });

    test('first byte of serialized data is type 9', () {
      final anim = PixelAnimationNormals();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      final buf = ByteData(22);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 9);
    });

    test('adds 3 gradient tracks to bits', () {
      final anim = PixelAnimationNormals();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      expect(bits.rgbTracks.length, 3);
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationNormals(durationMs: 3000, axisScaleTimes1000: 1500);
      final restored = PixelAnimationNormals.fromJson(anim.toJson());
      expect(restored.durationMs, 3000);
      expect(restored.axisScaleTimes1000, 1500);
    });
  });

  group('PixelAnimationGradientPattern', () {
    test('byteSize is 12', () {
      expect(PixelAnimationGradientPattern().byteSize, 12);
    });

    test('type is gradientPattern (4)', () {
      expect(PixelAnimationGradientPattern().type, PixelAnimationType.gradientPattern);
    });

    test('first byte of serialized data is type 4', () {
      final anim = PixelAnimationGradientPattern();
      final bits = AnimationBits();
      anim.prepareBits(bits);
      final buf = ByteData(12);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 4);
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationGradientPattern(durationMs: 1800, overrideWithFace: true);
      final restored = PixelAnimationGradientPattern.fromJson(anim.toJson());
      expect(restored.durationMs, 1800);
      expect(restored.overrideWithFace, true);
    });
  });

  group('PixelAnimationSequence', () {
    test('byteSize is 22', () {
      expect(PixelAnimationSequence().byteSize, 22);
    });

    test('type is sequence (10)', () {
      expect(PixelAnimationSequence().type, PixelAnimationType.sequence);
    });

    test('first byte of serialized data is type 10', () {
      final anim = PixelAnimationSequence(entries: [(0, 100), (12, 200)]);
      final bits = AnimationBits();
      final buf = ByteData(22);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint8(0), 10);
    });

    test('entry count clamped to 4', () {
      final anim = PixelAnimationSequence(entries: [(0,0),(12,0),(24,0),(36,0),(48,0)]);
      final bits = AnimationBits();
      final buf = ByteData(22);
      anim.writeTo(buf, 0, bits);
      expect(buf.getUint16(20, Endian.little), 4); // animationCount field
    });

    test('JSON round-trip', () {
      final anim = PixelAnimationSequence(durationMs: 1000, entries: [(0, 100), (20, 200)]);
      final restored = PixelAnimationSequence.fromJson(anim.toJson());
      expect(restored.entries.length, 2);
      expect(restored.entries[0].$2, 100);
    });
  });

  group('DataSet alignment (multi-gradient)', () {
    test('bits size padding does not cause buffer overflow', () {
      // Profile whose finalBitsSize is not 4-aligned — previously caused buffer overflow.
      final profile = PixelProfile(
        id: 'test', name: 'Multi',
        animations: [
          PixelAnimationNoise(), // adds 2 rgb tracks
          PixelAnimationNoise(), // adds 2 more
        ],
        rules: [
          PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)]),
          PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 1)]),
        ],
      );
      expect(() => PixelDataSet(profile).toByteArray(), returnsNormally);
      expect(() => PixelDataSet(profile).toAnimationsByteArray(), returnsNormally);
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
