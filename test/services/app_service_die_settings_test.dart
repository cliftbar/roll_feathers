import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';

void main() {
  group('DieSettings serialization', () {
    test('round-trip with all fields set', () {
      final settings = DieSettings(
        blinkColor: Colors.red,
        haEntityTargets: ['light.living_room'],
        faceTypeName: 'd20',
        rollingFlashEnabled: true,
        rollingFlashColor: Colors.blue,
        rollingFlashPreset: RollingFlashPreset.pulse,
      );

      final json = settings.toJson();
      final restored = DieSettings.fromJson(json);

      expect(restored.blinkColor?.toARGB32(), equals(Colors.red.toARGB32()));
      expect(restored.haEntityTargets, equals(['light.living_room']));
      expect(restored.faceTypeName, equals('d20'));
      expect(restored.rollingFlashEnabled, isTrue);
      expect(restored.rollingFlashColor?.toARGB32(), equals(Colors.blue.toARGB32()));
      expect(restored.rollingFlashPreset, equals(RollingFlashPreset.pulse));
    });

    test('round-trip with null color fields', () {
      final settings = DieSettings(
        blinkColor: null,
        rollingFlashColor: null,
      );

      final json = settings.toJson();
      final restored = DieSettings.fromJson(json);

      expect(restored.blinkColor, isNull);
      expect(restored.rollingFlashColor, isNull);
    });

    test('all RollingFlashPreset values survive round-trip', () {
      for (final preset in RollingFlashPreset.values) {
        final settings = DieSettings(rollingFlashPreset: preset);
        final restored = DieSettings.fromJson(settings.toJson());
        expect(restored.rollingFlashPreset, equals(preset));
      }
    });

    test('defaults match expected values', () {
      final settings = DieSettings();

      expect(settings.blinkColor, isNull);
      expect(settings.haEntityTargets, isEmpty);
      expect(settings.faceTypeName, isNull);
      expect(settings.rollingFlashEnabled, isFalse);
      expect(settings.rollingFlashColor, isNull);
      expect(settings.rollingFlashPreset, equals(RollingFlashPreset.strobe));
    });
  });

  group('InMemoryAppService die settings', () {
    late InMemoryAppService service;

    setUp(() => service = InMemoryAppService());

    test('getDieSettings returns null for unknown dieId', () async {
      expect(await service.getDieSettings('unknown-id'), isNull);
    });

    test('saveDieSettings then getDieSettings returns equal object', () async {
      final settings = DieSettings(
        blinkColor: Colors.green,
        rollingFlashEnabled: true,
        rollingFlashPreset: RollingFlashPreset.breathe,
      );

      await service.saveDieSettings('die-uuid-1', settings);
      final loaded = await service.getDieSettings('die-uuid-1');

      expect(loaded, isNotNull);
      expect(loaded!.blinkColor?.toARGB32(), equals(Colors.green.toARGB32()));
      expect(loaded.rollingFlashEnabled, isTrue);
      expect(loaded.rollingFlashPreset, equals(RollingFlashPreset.breathe));
    });

    test('settings are keyed per dieId independently', () async {
      await service.saveDieSettings('die-1', DieSettings(blinkColor: Colors.red));
      await service.saveDieSettings('die-2', DieSettings(blinkColor: Colors.blue));

      final die1 = await service.getDieSettings('die-1');
      final die2 = await service.getDieSettings('die-2');

      expect(die1!.blinkColor?.toARGB32(), equals(Colors.red.toARGB32()));
      expect(die2!.blinkColor?.toARGB32(), equals(Colors.blue.toARGB32()));
    });

    test('overwrite replaces previous settings', () async {
      await service.saveDieSettings('die-1', DieSettings(blinkColor: Colors.red));
      await service.saveDieSettings('die-1', DieSettings(blinkColor: Colors.purple));

      final loaded = await service.getDieSettings('die-1');
      expect(loaded!.blinkColor?.toARGB32(), equals(Colors.purple.toARGB32()));
    });
  });
}
