import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_builtin_animations.dart';

void main() {
  // ── Catalogue invariants ──────────────────────────────────────────────────

  group('kBuiltinAnimations catalogue', () {
    test('has exactly 62 presets', () {
      expect(kBuiltinAnimations.length, 62);
    });

    test('all names are unique', () {
      final names = kBuiltinAnimations.map((p) => p.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('all categories are valid', () {
      const valid = {'colorful', 'flashy', 'animated', 'uniform'};
      for (final p in kBuiltinAnimations) {
        expect(valid, contains(p.category),
            reason: '${p.name} has unknown category "${p.category}"');
      }
    });

    test('build(0) returns non-empty list for every preset', () {
      for (final p in kBuiltinAnimations) {
        final anims = p.build(0);
        expect(anims, isNotEmpty, reason: '${p.name} build returned empty');
      }
    });

    test('standalone presets build exactly 1 animation', () {
      final sequences = {
        'Rainbow Fountain X3',
        'Spiral Up and Down',
        'Spiral Up and Down Rainbow',
        'Alternating White',
        'Noise Rainbow X2',
        'Fire',
        'Overlapping Quick Reds',
        'Overlapping Quick Greens',
        'Rose to Current Face',
        'Double Spinning Magic',
        'Water Splash',
      };
      for (final p in kBuiltinAnimations) {
        if (!sequences.contains(p.name)) {
          expect(p.build(0).length, 1,
              reason: '${p.name} should be standalone (1 anim)');
        }
      }
    });

    test('sequence presets have ≥2 animations and last is PixelAnimationSequence', () {
      final sequences = {
        'Rainbow Fountain X3',
        'Spiral Up and Down',
        'Spiral Up and Down Rainbow',
        'Alternating White',
        'Noise Rainbow X2',
        'Fire',
        'Overlapping Quick Reds',
        'Overlapping Quick Greens',
        'Rose to Current Face',
        'Double Spinning Magic',
        'Water Splash',
      };
      for (final name in sequences) {
        final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
        final anims = p.build(0);
        expect(anims.length, greaterThanOrEqualTo(2),
            reason: '$name must have sub-anims + sequence');
        expect(anims.last, isA<PixelAnimationSequence>(),
            reason: '$name last element must be PixelAnimationSequence');
      }
    });

    test('sequence entries reference valid baseIndex offsets', () {
      final sequences = {
        'Rainbow Fountain X3',
        'Spiral Up and Down',
        'Spiral Up and Down Rainbow',
        'Alternating White',
        'Noise Rainbow X2',
        'Fire',
        'Overlapping Quick Reds',
        'Overlapping Quick Greens',
        'Rose to Current Face',
        'Double Spinning Magic',
        'Water Splash',
      };
      const base = 10;
      for (final name in sequences) {
        final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
        final anims = p.build(base);
        final seq = anims.last as PixelAnimationSequence;
        final subCount = anims.length - 1;
        for (final (idx, _) in seq.entries) {
          expect(idx, greaterThanOrEqualTo(base),
              reason: '$name entry index $idx below baseIndex $base');
          expect(idx, lessThan(base + subCount),
              reason: '$name entry index $idx out of sub-anim range');
        }
      }
    });
  });

  // ── Rainbow group ─────────────────────────────────────────────────────────

  group('Rainbow animations', () {
    PixelAnimationRainbow get(String name) {
      final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
      return p.build(0).first as PixelAnimationRainbow;
    }

    test('Rainbow is traveling, 5s, count=4, intensity=255, cycles=10', () {
      final a = get('Rainbow');
      expect(a.animFlags, 3);
      expect(a.durationMs, 5000);
      expect(a.count, 4);
      expect(a.intensity, 255);
      expect(a.cyclesTimes10, 10);
    });

    test('Rainbow Aurora has intensity=51', () {
      expect(get('Rainbow Aurora').intensity, 51);
    });

    test('Rainbow Fast is 3s count=9 cycles=30', () {
      final a = get('Rainbow Fast');
      expect(a.durationMs, 3000);
      expect(a.count, 9);
      expect(a.cyclesTimes10, 30);
    });

    test('Rainbow All Faces has animFlags=0', () {
      expect(get('Rainbow All Faces').animFlags, 0);
    });

    test('Fixed Rainbow count=0 cycles=20', () {
      final a = get('Fixed Rainbow');
      expect(a.count, 0);
      expect(a.cyclesTimes10, 20);
    });

    test('all Rainbow presets have fade=26', () {
      for (final name in [
        'Rainbow', 'Rainbow Aurora', 'Rainbow Fast',
        'Rainbow All Faces', 'Rainbow All Faces Aurora',
        'Rainbow All Faces Fast', 'Fixed Rainbow',
      ]) {
        expect(get(name).fade, 26, reason: '$name fade should be 26');
      }
    });
  });

  // ── Cycle group ───────────────────────────────────────────────────────────

  group('Cycle animations', () {
    PixelAnimationCycle get(String name) {
      final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
      return p.build(0).first as PixelAnimationCycle;
    }

    test('Cycle Fire: animFlags=ledIndices, 3s, count=5, cycles=15', () {
      final a = get('Cycle Fire');
      expect(a.animFlags, 2);
      expect(a.durationMs, 3000);
      expect(a.count, 5);
      expect(a.cyclesTimes10, 15);
    });

    test('Cycle Water: count=6, cycles=10', () {
      final a = get('Cycle Water');
      expect(a.count, 6);
      expect(a.cyclesTimes10, 10);
    });

    test('Cycle Magic: cycles=50', () {
      expect(get('Cycle Magic').cyclesTimes10, 50);
    });

    test('Red Blue Worm: 5s, cycles=8', () {
      final a = get('Red Blue Worm');
      expect(a.durationMs, 5000);
      expect(a.cyclesTimes10, 8);
    });

    test('Water Worm: 2s, count=2', () {
      final a = get('Water Worm');
      expect(a.durationMs, 2000);
      expect(a.count, 2);
    });

    test('all Cycle animations use ledIndices animFlag', () {
      for (final name in [
        'Cycle Fire', 'Cycle Water', 'Cycle Magic',
        'Red Blue Worm', 'Green Blue Worm', 'Pink Worm', 'Water Worm',
      ]) {
        expect(get(name).animFlags, 2,
            reason: '$name should use ledIndices animFlag');
      }
    });
  });

  // ── Noise group ───────────────────────────────────────────────────────────

  group('Noise animations', () {
    PixelAnimationNoise get(String name) {
      final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
      return p.build(0).first as PixelAnimationNoise;
    }

    test('Noise: 2s, blinkFreq=50000, blinkDur=510, fade=128, colorType=3, colorVar=20', () {
      final a = get('Noise');
      expect(a.durationMs, 2000);
      expect(a.blinkFrequencyTimes1000, 50000);
      expect(a.blinkDuration, 510);
      expect(a.fade, 128);
      expect(a.gradientColorType, 3);
      expect(a.gradientColorVar, 20);
    });

    test('Noise Rainbow: blinkFreq=40000, fade=26, no colorType', () {
      final a = get('Noise Rainbow');
      expect(a.blinkFrequencyTimes1000, 40000);
      expect(a.fade, 26);
      expect(a.gradientColorType, 0);
    });

    test('Rainbow Noise: 5s, colorType=1 (randomFromGradient), colorVar=0', () {
      final a = get('Rainbow Noise');
      expect(a.durationMs, 5000);
      expect(a.gradientColorType, 1);
      expect(a.gradientColorVar, 0);
    });

    test('Short Noise: 1s, blinkFreq=20000, blinkDur=255, colorVar=100', () {
      final a = get('Short Noise');
      expect(a.durationMs, 1000);
      expect(a.blinkFrequencyTimes1000, 20000);
      expect(a.blinkDuration, 255);
      expect(a.gradientColorVar, 100);
    });

    test('Fire Noise Layer: 5.5s, blinkFreqVar=1000, fade=255', () {
      final a = get('Fire Noise Layer');
      expect(a.durationMs, 5500);
      expect(a.blinkFrequencyVarTimes1000, 1000);
      expect(a.fade, 255);
    });

    test('White Noise: 1.5s, solid white gradient', () {
      final a = get('White Noise');
      expect(a.durationMs, 1500);
      expect(a.gradient.keyframes.first.$2.r, 255);
      expect(a.gradient.keyframes.first.$2.g, 255);
      expect(a.gradient.keyframes.first.$2.b, 255);
    });
  });

  // ── Key Normals spot-checks ────────────────────────────────────────────────

  group('Normals animations', () {
    PixelAnimationNormals get(String name) {
      final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
      return p.build(0).first as PixelAnimationNormals;
    }

    test('Waterfall: 2s, axisScale=2000, axisOffset=-500, axisScroll=2000, colorType=2', () {
      final a = get('Waterfall');
      expect(a.durationMs, 2000);
      expect(a.axisScaleTimes1000, 2000);
      expect(a.axisOffsetTimes1000, -500);
      expect(a.axisScrollSpeedTimes1000, 2000);
      expect(a.mainGradientColorType, 2);
      expect(a.mainGradientColorVar, 100);
    });

    test('Waterfall Gradient: colorType=1 (faceToGradient)', () {
      expect(get('Waterfall Gradient').mainGradientColorType, 1);
    });

    test('Waterfall Top Half: 500ms, axisScale=1000, axisOffset=0, axisScroll=0', () {
      final a = get('Waterfall Top Half');
      expect(a.durationMs, 500);
      expect(a.axisScaleTimes1000, 1000);
      expect(a.axisOffsetTimes1000, 0);
      expect(a.axisScrollSpeedTimes1000, 0);
    });

    test('Spinning: 3s, angleScroll=8000, colorType=2', () {
      final a = get('Spinning');
      expect(a.durationMs, 3000);
      expect(a.angleScrollSpeedTimes1000, 8000);
      expect(a.mainGradientColorType, 2);
    });

    test('Spinning Rainbow: 5s, angleScroll=10000', () {
      final a = get('Spinning Rainbow');
      expect(a.durationMs, 5000);
      expect(a.angleScrollSpeedTimes1000, 10000);
    });

    test('Spiral Up: 1.5s, axisOffset=1100, axisScroll=-2200, colorType=2', () {
      final a = get('Spiral Up');
      expect(a.durationMs, 1500);
      expect(a.axisOffsetTimes1000, 1100);
      expect(a.axisScrollSpeedTimes1000, -2200);
      expect(a.mainGradientColorType, 2);
    });

    test('Spiral Down: axisOffset=-1200, axisScroll=2200', () {
      final a = get('Spiral Down');
      expect(a.axisOffsetTimes1000, -1200);
      expect(a.axisScrollSpeedTimes1000, 2200);
    });

    test('Rainbow Up: 3s, axisOffset=800, axisScroll=-2200, colorType=0', () {
      final a = get('Rainbow Up');
      expect(a.durationMs, 3000);
      expect(a.axisOffsetTimes1000, 800);
      expect(a.axisScrollSpeedTimes1000, -2200);
      expect(a.mainGradientColorType, 0);
    });

    test('Rainbow Down: axisOffset=-800, axisScroll=2200', () {
      final a = get('Rainbow Down');
      expect(a.axisOffsetTimes1000, -800);
      expect(a.axisScrollSpeedTimes1000, 2200);
    });

    test('Counter Spinning Magic: angleScroll=5142', () {
      expect(get('Counter Spinning Magic').angleScrollSpeedTimes1000, 5142);
    });

    test('Fountain: axisOffset=1000, axisScroll=-2000, colorType=2', () {
      final a = get('Fountain');
      expect(a.axisOffsetTimes1000, 1000);
      expect(a.axisScrollSpeedTimes1000, -2000);
      expect(a.mainGradientColorType, 2);
    });

    test('Rainbow Fountain: colorVar=500', () {
      expect(get('Rainbow Fountain').mainGradientColorVar, 500);
    });

    test('Fire Base Layer: 4.5s', () {
      expect(get('Fire Base Layer').durationMs, 4500);
    });

    test('Water Base Layer: 4.5s, axisOffset=-1000, axisScroll=2000', () {
      final a = get('Water Base Layer');
      expect(a.durationMs, 4500);
      expect(a.axisOffsetTimes1000, -1000);
      expect(a.axisScrollSpeedTimes1000, 2000);
    });
  });

  // ── Flash animations ──────────────────────────────────────────────────────

  group('Flash animations', () {
    PixelAnimationSimple get(String name) {
      final p = kBuiltinAnimations.firstWhere((x) => x.name == name);
      return p.build(0).first as PixelAnimationSimple;
    }

    test('Blue Flash: 1s, blue, fade=128', () {
      final a = get('Blue Flash');
      expect(a.durationMs, 1000);
      expect(a.color.b, 179);
      expect(a.fade, 128);
    });

    test('White Flash: 300ms, brightWhite, count=1, fade=128', () {
      final a = get('White Flash');
      expect(a.durationMs, 300);
      expect(a.color.r, 255);
      expect(a.count, 1);
      expect(a.fade, 128);
    });

    test('Colored Flash: faceColor=true', () {
      expect(get('Colored Flash').faceColor, true);
    });

    test('Alternate White 1: 3s, count=5, fade=255, faceMask=91543', () {
      final a = get('Alternate White 1');
      expect(a.durationMs, 3000);
      expect(a.count, 5);
      expect(a.fade, 255);
      expect(a.faceMask, 91543);
    });

    test('Alternate White 2: fade=128, faceMask=957032', () {
      final a = get('Alternate White 2');
      expect(a.fade, 128);
      expect(a.faceMask, 957032);
    });
  });

  // ── Sequence presets ──────────────────────────────────────────────────────

  group('Sequence presets', () {
    test('Rainbow Fountain X3: 1 sub-anim, 3 entries all at base', () {
      const base = 5;
      final p = kBuiltinAnimations.firstWhere((x) => x.name == 'Rainbow Fountain X3');
      final anims = p.build(base);
      expect(anims.length, 2); // 1 sub + sequence
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.durationMs, 7000);
      expect(seq.entries.length, 3);
      for (final (idx, _) in seq.entries) {
        expect(idx, base); // all point to the same sub-anim
      }
      expect(seq.entries[1].$2, 1400);
      expect(seq.entries[2].$2, 2800);
    });

    test('Spiral Up and Down: 2 sub-anims, entries at base and base+1', () {
      const base = 3;
      final p = kBuiltinAnimations.firstWhere((x) => x.name == 'Spiral Up and Down');
      final anims = p.build(base);
      expect(anims.length, 3);
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.entries[0], (base, 0));
      expect(seq.entries[1].$1, base + 1);
      expect(seq.entries[1].$2, 700);
    });

    test('Alternating White: 3 sub-anims, delays 0/150/450', () {
      const base = 0;
      final p = kBuiltinAnimations.firstWhere((x) => x.name == 'Alternating White');
      final anims = p.build(base);
      expect(anims.length, 4);
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.durationMs, 7000);
      expect(seq.entries[0].$2, 0);
      expect(seq.entries[1].$2, 150);
      expect(seq.entries[2].$2, 450);
    });

    test('Noise Rainbow X2: 2 sub-anims, noiseRainbow referenced twice', () {
      const base = 0;
      final p = kBuiltinAnimations.firstWhere((x) => x.name == 'Noise Rainbow X2');
      final anims = p.build(base);
      expect(anims.length, 3);
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.entries.length, 3);
      expect(seq.entries[1].$1, seq.entries[2].$1); // same sub-anim index
      expect(seq.entries[2].$2, 2000);
    });

    test('Fire: 2 sub-anims at delay 0', () {
      const base = 0;
      final p = kBuiltinAnimations.firstWhere((x) => x.name == 'Fire');
      final anims = p.build(base);
      expect(anims.length, 3);
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.entries[0].$2, 0);
      expect(seq.entries[1].$2, 0);
    });

    test('Overlapping Quick Greens: 1 sub-anim, 3 entries at 0/800/1600', () {
      const base = 7;
      final p = kBuiltinAnimations
          .firstWhere((x) => x.name == 'Overlapping Quick Greens');
      final anims = p.build(base);
      expect(anims.length, 2);
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.entries[0], (base, 0));
      expect(seq.entries[1], (base, 800));
      expect(seq.entries[2], (base, 1600));
    });

    test('Double Spinning Magic: 1 sub-anim, 1 entry at delay 0', () {
      final p = kBuiltinAnimations
          .firstWhere((x) => x.name == 'Double Spinning Magic');
      final anims = p.build(0);
      expect(anims.length, 2);
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.entries.length, 1);
      expect(seq.entries.first.$2, 0);
    });

    test('Water Splash: waterWorm sub-anim + longBlueFlash at delay 1000', () {
      final p = kBuiltinAnimations.firstWhere((x) => x.name == 'Water Splash');
      final anims = p.build(0);
      expect(anims.length, 3);
      expect(anims[0], isA<PixelAnimationCycle>());
      expect(anims[1], isA<PixelAnimationSimple>());
      final flash = anims[1] as PixelAnimationSimple;
      expect(flash.durationMs, 2000);
      expect(flash.color.r, 162); // PixelColor(162, 207, 252)
      final seq = anims.last as PixelAnimationSequence;
      expect(seq.entries[1].$2, 1000);
    });
  });
}
