import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_builtin_profiles.dart';

// ─── helpers ─────────────────────────────────────────────────────────────────

// Official profiles include 7 advanced animations + rules prepended.
const int kAdvanced = 7;

PixelProfile _build(String name) =>
    kBuiltinProfiles.firstWhere((p) => p.name == name).build();

void main() {
  group('kBuiltinProfiles', () {
    test('contains 17 profiles', () {
      expect(kBuiltinProfiles.length, 17);
    });

    test('all profile names are unique', () {
      final names = kBuiltinProfiles.map((p) => p.name).toList();
      expect(names.toSet().length, names.length);
    });

    for (final preset in kBuiltinProfiles) {
      group(preset.name, () {
        late PixelProfile profile;

        setUp(() => profile = preset.build());

        test('id is blank (caller assigns UUID)', () {
          expect(profile.id, isEmpty);
        });

        test('has at least one animation', () {
          expect(profile.animations, isNotEmpty);
        });

        test('has at least one rule', () {
          expect(profile.rules, isNotEmpty);
        });

        test('all rule animIndex values are in-bounds', () {
          for (final rule in profile.rules) {
            for (final action
                in rule.actions.whereType<PixelActionPlayAnimation>()) {
              expect(
                action.animIndex,
                lessThan(profile.animations.length),
                reason:
                    'animIndex ${action.animIndex} out of range for '
                    '${profile.animations.length} animations',
              );
            }
          }
        });

        test('serializes to DataSet without error', () {
          expect(() => PixelDataSet(profile).toByteArray(), returnsNormally);
        });

        test('DataSet has non-zero size', () {
          expect(PixelDataSet(profile).toByteArray().length, greaterThan(0));
        });

        test('JSON round-trips correctly', () {
          final json = profile.toJson();
          final restored = PixelProfile.fromJson(json);
          expect(restored.name, profile.name);
          expect(restored.animations.length, profile.animations.length);
          expect(restored.rules.length, profile.rules.length);
        });

        test('instant transfer stats have valid hash', () {
          final stats = PixelDataSet(profile).computeInstantStats();
          expect(stats.hash, isNonZero);
          expect(stats.animationCount, profile.animations.length);
        });
      });
    }
  });

  // ─── Default Profile ───────────────────────────────────────────────────────
  // 7 advanced + 4 profile-specific rules (rolling, top, middle, low)

  group('Default Profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Default Profile'));

    test('has 11 rules (7 advanced + rolling + top + middle + low)', () {
      expect(profile.rules.length, kAdvanced + 4);
    });

    test('has 10 animations (7 advanced + coloredFlash + waterfall + quickRed)', () {
      expect(profile.animations.length, kAdvanced + 3);
    });

    test('has HelloGoodbye condition (hello only) from advanced rules', () {
      final hg = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionHelloGoodbye>()
          .first;
      expect(hg.flags & 1, 1); // hello
      expect(hg.flags & 2, 0); // no goodbye
    });

    test('has ConnectionState condition from advanced rules', () {
      expect(
        profile.rules.any((r) => r.condition is PixelConditionConnectionState),
        isTrue,
      );
    });

    test('has BatteryState conditions from advanced rules', () {
      final batt = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionBatteryState>()
          .toList();
      expect(batt.length, 5);
    });

    test('Rolling condition has 500 ms recheck', () {
      final rolling = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionRolling>()
          .first;
      expect(rolling.repeatPeriodMs, 500);
    });

    test('rolling rule plays coloredFlash (faceColor, anim 7)', () {
      final rule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionRolling,
      );
      final action = rule.actions.first as PixelActionPlayAnimation;
      expect(action.animIndex, kAdvanced + 0);
      final anim = profile.animations[action.animIndex] as PixelAnimationSimple;
      expect(anim.faceColor, isTrue);
    });

    test('top rolled rule reuses hello rainbow (anim 0)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x80000;
      });
      expect((rule.actions.first as PixelActionPlayAnimation).animIndex, 0);
    });

    test('middle rolled rule plays waterfall (anim 8)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFE;
      });
      expect(
        (rule.actions.first as PixelActionPlayAnimation).animIndex,
        kAdvanced + 1,
      );
    });

    test('low rolled rule plays quickRed (anim 9)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x1;
      });
      expect(
        (rule.actions.first as PixelActionPlayAnimation).animIndex,
        kAdvanced + 2,
      );
    });
  });

  // ─── High Low ──────────────────────────────────────────────────────────────

  group('High Low profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('High Low'));

    test('has 10 rules (7 advanced + rolling + low + high)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 13 animations (7 advanced + 6 profile-specific)', () {
      expect(profile.animations.length, kAdvanced + 6);
    });

    test('low-face condition uses faces 1–10 bitmask', () {
      final rolled = profile.rules
          .where((r) => r.condition is PixelConditionRolled)
          .map((r) => r.condition as PixelConditionRolled)
          .toList();
      expect(rolled.any((c) => c.faceMask == 0x3FF), isTrue);
    });

    test('high-face condition uses faces 11–20 bitmask', () {
      final rolled = profile.rules
          .where((r) => r.condition is PixelConditionRolled)
          .map((r) => r.condition as PixelConditionRolled)
          .toList();
      expect(rolled.any((c) => c.faceMask == 0xFFC00), isTrue);
    });

    test('rolling animation is Simple type (blueFlash at anim 7)', () {
      final rule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionRolling,
      );
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      expect(animIdx, kAdvanced);
      final anim = profile.animations[animIdx] as PixelAnimationSimple;
      expect(anim.color.r, 0);
      expect(anim.color.g, 0);
      expect(anim.color.b, greaterThan(0));
    });
  });

  // ─── Flashy ────────────────────────────────────────────────────────────────

  group('Flashy profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Flashy'));

    test('has 9 animations (7 advanced + coloredFlash + rainbowAllFacesFast)', () {
      expect(profile.animations.length, kAdvanced + 2);
    });

    test('has 10 rules (7 advanced + rolling + non-top + top)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('coloredFlash animation uses faceColor', () {
      final anim = profile.animations[kAdvanced] as PixelAnimationSimple;
      expect(anim.faceColor, isTrue);
    });

    test('nat-20 rule animation is Rainbow type', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x80000;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      expect(profile.animations[animIdx], isA<PixelAnimationRainbow>());
    });

    test('nat-20 rule loops 2 times', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x80000;
      });
      expect((rule.actions.first as PixelActionPlayAnimation).loopCount, 2);
    });

    test('non-top rolled action loops 5 times', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      expect((rule.actions.first as PixelActionPlayAnimation).loopCount, 5);
    });
  });

  // ─── Rainbow ───────────────────────────────────────────────────────────────

  group('Rainbow profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Rainbow'));

    test('all animations are Rainbow type', () {
      for (final a in profile.animations) {
        expect(a, isA<PixelAnimationRainbow>());
      }
    });
  });

  // ─── Color Cycle ───────────────────────────────────────────────────────────

  group('Color Cycle profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Color Cycle'));

    test('all animations are Cycle type', () {
      for (final a in profile.animations) {
        expect(a, isA<PixelAnimationCycle>());
      }
    });

    test('has 3 animations', () {
      expect(profile.animations.length, 3);
    });
  });

  // ─── Empty ─────────────────────────────────────────────────────────────────

  group('Empty profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Empty'));

    test('has exactly 7 animations (all advanced)', () {
      expect(profile.animations.length, kAdvanced);
    });

    test('has exactly 7 rules (all advanced)', () {
      expect(profile.rules.length, kAdvanced);
    });

    test('first rule is HelloGoodbye condition', () {
      expect(profile.rules.first.condition, isA<PixelConditionHelloGoodbye>());
    });

    test('first animation is Rainbow type (hello rainbow)', () {
      expect(profile.animations.first, isA<PixelAnimationRainbow>());
    });
  });

  // ─── Speak Numbers ─────────────────────────────────────────────────────────

  group('Speak Numbers profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Speak Numbers'));

    test('has 29 rules (7 advanced + noise + noiseRainbow + 20 speak)', () {
      expect(profile.rules.length, kAdvanced + 2 + 20);
    });

    test('has 9 animations (7 advanced + noise + noiseRainbow)', () {
      expect(profile.animations.length, kAdvanced + 2);
    });

    test('has 20 SpeakText rules (one per face)', () {
      final speak = profile.rules
          .expand((r) => r.actions)
          .whereType<PixelActionSpeakText>()
          .toList();
      expect(speak.length, 20);
    });

    test('speak texts are face numbers 1–20', () {
      final texts = profile.rules
          .expand((r) => r.actions)
          .whereType<PixelActionSpeakText>()
          .map((a) => a.text)
          .toSet();
      expect(texts, {for (var f = 1; f <= 20; f++) '$f'});
    });

    test('noise animation at index 7 is Noise type', () {
      expect(profile.animations[kAdvanced], isA<PixelAnimationNoise>());
    });

    test('noiseRainbow animation at index 8 is Noise type', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationNoise>());
    });

    test('HG rule (from advanced) plays hello rainbow (anim 0)', () {
      final hgRule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionHelloGoodbye,
      );
      expect(
        (hgRule.actions.first as PixelActionPlayAnimation).animIndex,
        0,
      );
      expect(profile.animations[0], isA<PixelAnimationRainbow>());
    });
  });

  // ─── Waterfall ─────────────────────────────────────────────────────────────

  group('Waterfall profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Waterfall'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 10 animations (7 advanced + waterfallTopHalf + waterfall + waterfallRainbow)', () {
      expect(profile.animations.length, kAdvanced + 3);
    });

    test('profile-specific animations are all Normals type', () {
      for (var i = kAdvanced; i < profile.animations.length; i++) {
        expect(profile.animations[i], isA<PixelAnimationNormals>());
      }
    });

    test('non-top rolled animation has positive axis scroll (band scrolls up)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationNormals;
      expect(anim.axisScrollSpeedTimes1000, greaterThan(0));
    });
  });

  // ─── Fountain ──────────────────────────────────────────────────────────────

  group('Fountain profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Fountain'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 11 animations (7 advanced + waterfallTopHalf + fountain + rainbowFountain + seq)', () {
      expect(profile.animations.length, kAdvanced + 4);
    });

    test('waterfallTopHalf is Normals type (anim 7)', () {
      expect(profile.animations[kAdvanced], isA<PixelAnimationNormals>());
    });

    test('fountain is Normals type (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationNormals>());
    });

    test('rainbowFountainX3 is Sequence type (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationSequence>());
    });

    test('rainbowFountain is Normals type (anim 10)', () {
      expect(profile.animations[kAdvanced + 3], isA<PixelAnimationNormals>());
    });

    test('non-top rolled animation has negative axis scroll (jets upward)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationNormals;
      expect(anim.axisScrollSpeedTimes1000, lessThan(0));
    });
  });

  // ─── Spinning ──────────────────────────────────────────────────────────────

  group('Spinning profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Spinning'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('profile-specific animations are all Normals type', () {
      for (var i = kAdvanced; i < profile.animations.length; i++) {
        expect(profile.animations[i], isA<PixelAnimationNormals>());
      }
    });

    test('spinning animation has high angle scroll (rotation)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationNormals;
      expect(anim.angleScrollSpeedTimes1000, greaterThan(0));
    });

    test('spinning animation has zero axis scroll', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationNormals;
      expect(anim.axisScrollSpeedTimes1000, 0);
    });
  });

  // ─── Spiral ────────────────────────────────────────────────────────────────

  group('Spiral profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Spiral'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 14 animations (7 advanced + 7 profile-specific)', () {
      expect(profile.animations.length, kAdvanced + 7);
    });

    test('waterfallTopHalf is Normals (anim 7)', () {
      expect(profile.animations[kAdvanced + 0], isA<PixelAnimationNormals>());
    });

    test('spiralUpDown is Sequence (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationSequence>());
    });

    test('spiralUp is Normals (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationNormals>());
    });

    test('spiralDown is Normals (anim 10)', () {
      expect(profile.animations[kAdvanced + 3], isA<PixelAnimationNormals>());
    });

    test('spiralUpDownRainbow is Sequence (anim 11)', () {
      expect(profile.animations[kAdvanced + 4], isA<PixelAnimationSequence>());
    });

    test('rainbowUp is Normals (anim 12)', () {
      expect(profile.animations[kAdvanced + 5], isA<PixelAnimationNormals>());
    });

    test('rainbowDown is Normals (anim 13)', () {
      expect(profile.animations[kAdvanced + 6], isA<PixelAnimationNormals>());
    });

    test('spiralUp has both axis and angle scroll', () {
      final spiralUp = profile.animations[kAdvanced + 2] as PixelAnimationNormals;
      expect(spiralUp.axisScrollSpeedTimes1000, isNot(0));
      expect(spiralUp.angleScrollSpeedTimes1000, greaterThan(0));
    });

    test('non-top rolled rule uses spiralUpDown sequence (index 8)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      expect(
        (rule.actions.first as PixelActionPlayAnimation).animIndex,
        kAdvanced + 1,
      );
    });
  });

  // ─── Noise ─────────────────────────────────────────────────────────────────

  group('Noise profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Noise'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 12 animations (7 advanced + shortNoise + noise + greenFlash + noiseRainbow + seq)', () {
      expect(profile.animations.length, kAdvanced + 5);
    });

    test('shortNoise is Noise type (anim 7)', () {
      expect(profile.animations[kAdvanced + 0], isA<PixelAnimationNoise>());
    });

    test('noise is Noise type (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationNoise>());
    });

    test('noiseRainbowX2 is Sequence type (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationSequence>());
    });

    test('greenFlash is Simple type (anim 10)', () {
      expect(profile.animations[kAdvanced + 3], isA<PixelAnimationSimple>());
    });

    test('noiseRainbow is Noise type (anim 11)', () {
      expect(profile.animations[kAdvanced + 4], isA<PixelAnimationNoise>());
    });

    test('rolling animation uses low blink frequency (shortNoise)', () {
      final rule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionRolling,
      );
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationNoise;
      expect(anim.blinkFrequencyTimes1000, lessThan(50000));
    });

    test('non-top rolled uses high blink frequency (noise)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationNoise;
      expect(anim.blinkFrequencyTimes1000, 50000);
    });
  });

  // ─── Worm ──────────────────────────────────────────────────────────────────

  group('Worm profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Worm'));

    test('has 12 rules (7 advanced + rolling + low + mid + high + top)', () {
      expect(profile.rules.length, kAdvanced + 5);
    });

    test('has 12 animations (7 advanced + 5 profile-specific)', () {
      expect(profile.animations.length, kAdvanced + 5);
    });

    test('rolling animation is Simple type (blueFlash at anim 7)', () {
      final rule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionRolling,
      );
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      expect(profile.animations[animIdx], isA<PixelAnimationSimple>());
    });

    test('low faces use Cycle type (redBlueWorm)', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7F;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      expect(profile.animations[animIdx], isA<PixelAnimationCycle>());
    });

    test('mid/high non-top faces use Cycle type (worm effect)', () {
      final wormRules = profile.rules.where((r) {
        final c = r.condition;
        return c is PixelConditionRolled &&
            (c.faceMask == 0x3F80 || c.faceMask == 0x7C000);
      });
      for (final r in wormRules) {
        final idx = (r.actions.first as PixelActionPlayAnimation).animIndex;
        expect(profile.animations[idx], isA<PixelAnimationCycle>());
      }
    });

    test('top face uses rainbowFast Rainbow', () {
      final rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x80000;
      });
      final animIdx = (rule.actions.first as PixelActionPlayAnimation).animIndex;
      expect(profile.animations[animIdx], isA<PixelAnimationRainbow>());
    });

    test('uses tier face bitmasks for low, mid, and high face groups', () {
      final rolledMasks = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionRolled>()
          .map((c) => c.faceMask)
          .toList();
      expect(rolledMasks, containsAll([0x7F, 0x3F80, 0x7C000]));
    });
  });

  // ─── Rose ──────────────────────────────────────────────────────────────────

  group('Rose profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Rose'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 10 animations (7 advanced + whiteRose + longWhiteFlash + roseToCurrentFace)', () {
      expect(profile.animations.length, kAdvanced + 3);
    });

    test('whiteRose is Normals type (anim 7)', () {
      expect(profile.animations[kAdvanced + 0], isA<PixelAnimationNormals>());
    });

    test('roseToCurrentFace is Sequence type (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationSequence>());
    });

    test('longWhiteFlash is Simple type (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationSimple>());
    });

    test('rolling rule plays whiteRose on face 19 with loopCount 1', () {
      final rule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionRolling,
      );
      final action = rule.actions.first as PixelActionPlayAnimation;
      expect(action.animIndex, kAdvanced + 0);
      expect(action.faceIndex, 19);
      expect(action.loopCount, 1);
    });

    test('rolled rules use roseToCurrentFace sequence (index 8)', () {
      final rolledRules = profile.rules
          .where((r) => r.condition is PixelConditionRolled)
          .toList();
      expect(rolledRules.length, 2);
      for (final r in rolledRules) {
        expect(
          (r.actions.first as PixelActionPlayAnimation).animIndex,
          kAdvanced + 1,
        );
      }
    });

    test('whiteRose has durationMs=5000, no scroll', () {
      final anim = profile.animations[kAdvanced + 0] as PixelAnimationNormals;
      expect(anim.durationMs, 5000);
      expect(anim.axisScrollSpeedTimes1000, 0);
      expect(anim.angleScrollSpeedTimes1000, 0);
    });
  });

  // ─── Fire ──────────────────────────────────────────────────────────────────

  group('Fire profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Fire'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 10 animations (7 advanced + fireBaseLayer + fireNoiseLayer + fire)', () {
      expect(profile.animations.length, kAdvanced + 3);
    });

    test('fire is Sequence type (anim 7)', () {
      expect(profile.animations[kAdvanced + 0], isA<PixelAnimationSequence>());
    });

    test('fireBaseLayer is Normals type (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationNormals>());
    });

    test('fireNoiseLayer is Noise type (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationNoise>());
    });

    test('uses non-top and top face masks for rolled rules', () {
      final rolledMasks = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionRolled>()
          .map((c) => c.faceMask)
          .toList();
      expect(rolledMasks, containsAll([0x7FFFF, 0x80000]));
    });
  });

  // ─── Magic ─────────────────────────────────────────────────────────────────

  group('Magic profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Magic'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 10 animations (7 advanced + spinningMagic + doubleSpinningMagic + cycleMagic)', () {
      expect(profile.animations.length, kAdvanced + 3);
    });

    test('doubleSpinningMagic is Sequence type (anim 7)', () {
      expect(profile.animations[kAdvanced + 0], isA<PixelAnimationSequence>());
    });

    test('spinningMagic is Normals type (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationNormals>());
    });

    test('cycleMagic is Cycle type (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationCycle>());
    });

    test('rolled rules use cycleMagic (index 9)', () {
      final rolledRules = profile.rules
          .where((r) => r.condition is PixelConditionRolled)
          .toList();
      expect(rolledRules.length, 2);
      for (final r in rolledRules) {
        expect(
          (r.actions.first as PixelActionPlayAnimation).animIndex,
          kAdvanced + 2,
        );
      }
    });
  });

  // ─── Water ─────────────────────────────────────────────────────────────────

  group('Water profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = _build('Water'));

    test('has 10 rules (7 advanced + rolling + non-top rolled + top rolled)', () {
      expect(profile.rules.length, kAdvanced + 3);
    });

    test('has 11 animations (7 advanced + waterBaseLayer + waterWorm + longBlueFlash + waterSplash)', () {
      expect(profile.animations.length, kAdvanced + 4);
    });

    test('waterBaseLayer is Normals type (anim 7)', () {
      expect(profile.animations[kAdvanced + 0], isA<PixelAnimationNormals>());
    });

    test('waterSplash is Sequence type (anim 8)', () {
      expect(profile.animations[kAdvanced + 1], isA<PixelAnimationSequence>());
    });

    test('waterWorm is Cycle type (anim 9)', () {
      expect(profile.animations[kAdvanced + 2], isA<PixelAnimationCycle>());
    });

    test('longBlueFlash is Simple type (anim 10)', () {
      expect(profile.animations[kAdvanced + 3], isA<PixelAnimationSimple>());
    });

    test('rolling rule plays waterBaseLayer on face 19', () {
      final rule = profile.rules.firstWhere(
        (r) => r.condition is PixelConditionRolling,
      );
      final action = rule.actions.first as PixelActionPlayAnimation;
      expect(action.animIndex, kAdvanced + 0);
      expect(action.faceIndex, 19);
      expect(action.loopCount, 1);
    });

    test('rolled rules use waterSplash sequence (index 8)', () {
      final rolledRules = profile.rules
          .where((r) => r.condition is PixelConditionRolled)
          .toList();
      expect(rolledRules.length, 2);
      for (final r in rolledRules) {
        expect(
          (r.actions.first as PixelActionPlayAnimation).animIndex,
          kAdvanced + 1,
        );
      }
    });

    test('waterBaseLayer has positive axis scroll and durationMs=4500', () {
      final anim = profile.animations[kAdvanced + 0] as PixelAnimationNormals;
      expect(anim.axisScrollSpeedTimes1000, greaterThan(0));
      expect(anim.durationMs, 4500);
    });
  });

  // ─── Advanced rules shared by all official profiles ────────────────────────

  group('Advanced rules (shared by all official profiles)', () {
    const officialNames = [
      'Default Profile',
      'High Low',
      'Flashy',
      'Empty',
      'Speak Numbers',
      'Waterfall',
      'Fountain',
      'Spinning',
      'Spiral',
      'Noise',
      'Worm',
      'Rose',
      'Fire',
      'Magic',
      'Water',
    ];

    for (final name in officialNames) {
      test('$name has 7 advanced animations first', () {
        final profile = _build(name);
        expect(profile.animations.length, greaterThanOrEqualTo(kAdvanced));
        expect(profile.animations[0], isA<PixelAnimationRainbow>()); // hello
        expect(profile.animations[1], isA<PixelAnimationSimple>()); // connection
        expect(profile.animations[2], isA<PixelAnimationSimple>()); // lowBattery
        expect(profile.animations[3], isA<PixelAnimationSimple>()); // charging
        expect(profile.animations[4], isA<PixelAnimationSimple>()); // charged
        expect(profile.animations[5], isA<PixelAnimationSimple>()); // badCharging
        expect(profile.animations[6], isA<PixelAnimationSimple>()); // chargingError
      });

      test('$name has 7 advanced rules first', () {
        final profile = _build(name);
        expect(profile.rules.length, greaterThanOrEqualTo(kAdvanced));
        expect(profile.rules[0].condition, isA<PixelConditionHelloGoodbye>());
        expect(profile.rules[1].condition, isA<PixelConditionConnectionState>());
        for (var i = 2; i < 7; i++) {
          expect(profile.rules[i].condition, isA<PixelConditionBatteryState>());
        }
      });
    }

    test('hello rule plays anim 0 (hello rainbow)', () {
      final profile = _build('Empty');
      final hgRule = profile.rules.first;
      expect(
        (hgRule.actions.first as PixelActionPlayAnimation).animIndex,
        0,
      );
    });

    test('hello rainbow is 2 s, fade=200, intensity=128, cyclesTimes10=10', () {
      final profile = _build('Empty');
      final anim = profile.animations[0] as PixelAnimationRainbow;
      expect(anim.durationMs, 2000);
      expect(anim.fade, 200);
      expect(anim.intensity, 128);
      expect(anim.cyclesTimes10, 10);
    });

    test('battery rules cover all 5 states (low/charging/done/badCharging/error)', () {
      final profile = _build('Empty');
      final battFlags = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionBatteryState>()
          .map((c) => c.flags)
          .toSet();
      expect(battFlags, containsAll([2, 4, 8, 16, 32]));
    });

    test('low-battery rule recheck is 30000 ms', () {
      final profile = _build('Empty');
      final low = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionBatteryState>()
          .firstWhere((c) => c.flags == 2);
      expect(low.repeatPeriodMs, 30000);
    });

    test('charging rule plays anim 3 with faceIndex 19', () {
      final profile = _build('Empty');
      final chargingRule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionBatteryState && c.flags == 4;
      });
      final action = chargingRule.actions.first as PixelActionPlayAnimation;
      expect(action.animIndex, 3);
      expect(action.faceIndex, 19);
    });
  });
}
