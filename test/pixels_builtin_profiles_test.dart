import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_builtin_profiles.dart';

void main() {
  group('kBuiltinProfiles', () {
    test('contains exactly 4 profiles', () {
      expect(kBuiltinProfiles.length, 4);
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
            for (final action in rule.actions.whereType<PixelActionPlayAnimation>()) {
              expect(
                action.animIndex,
                lessThan(profile.animations.length),
                reason: 'animIndex ${action.animIndex} out of range for ${profile.animations.length} animations',
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

  group('Default profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = kBuiltinProfiles.firstWhere((p) => p.name == 'Default').build());

    test('has HelloGoodbye condition', () {
      final conds = profile.rules.map((r) => r.condition);
      expect(conds.any((c) => c is PixelConditionHelloGoodbye), isTrue);
    });

    test('HelloGoodbye flags cover both hello and goodbye', () {
      final hg = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionHelloGoodbye>()
          .first;
      expect(hg.flags & 1, 1); // hello
      expect(hg.flags & 2, 2); // goodbye
    });

    test('has Rolling condition with 200 ms period', () {
      final rolling = profile.rules
          .map((r) => r.condition)
          .whereType<PixelConditionRolling>()
          .first;
      expect(rolling.repeatPeriodMs, 200);
    });

    test('rolled animation covers all faces', () {
      final rolled = profile.rules.firstWhere((r) => r.condition is PixelConditionRolled);
      final cond = rolled.condition as PixelConditionRolled;
      expect(cond.faceMask, 0xFFFFF);
    });
  });

  group('High / Low profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = kBuiltinProfiles.firstWhere((p) => p.name == 'High / Low').build());

    test('has three animations (rolling + low + high)', () {
      expect(profile.animations.length, 3);
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

    test('rolling animation is blue', () {
      final anim = profile.animations.first as PixelAnimationSimple;
      expect(anim.color.r, 0);
      expect(anim.color.g, 0);
      expect(anim.color.b, 255);
    });
  });

  group('Flashy profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = kBuiltinProfiles.firstWhere((p) => p.name == 'Flashy').build());

    test('nat-20 animation is a Rainbow', () {
      final nat20Rule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x80000;
      });
      final animIdx = (nat20Rule.actions.first as PixelActionPlayAnimation).animIndex;
      expect(profile.animations[animIdx], isA<PixelAnimationRainbow>());
    });

    test('non-20 animation repeats 5 times', () {
      final nonTopRule = profile.rules.firstWhere((r) {
        final c = r.condition;
        return c is PixelConditionRolled && c.faceMask == 0x7FFFF;
      });
      final animIdx = (nonTopRule.actions.first as PixelActionPlayAnimation).animIndex;
      final anim = profile.animations[animIdx] as PixelAnimationSimple;
      expect(anim.count, 5);
    });
  });

  group('Rainbow profile specifics', () {
    late PixelProfile profile;
    setUp(() => profile = kBuiltinProfiles.firstWhere((p) => p.name == 'Rainbow').build());

    test('all animations are Rainbow type', () {
      for (final a in profile.animations) {
        expect(a, isA<PixelAnimationRainbow>());
      }
    });
  });
}
