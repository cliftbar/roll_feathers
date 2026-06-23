import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';

import '../test_util.dart';

class MockBleDeviceWrapper extends Mock implements BleDeviceWrapper {}

List<int> _buildTestIAmADie() => [
  pix.PixelMessageType.iAmADie.index,
  20, 0, pix.PixelDieType.d20.index,
  0, 0, 0, 0, // dataSetHash
  1, 0, 0, 0, // pixelId
  0, 0, // availableFlash
  0, 0, 0, 0, // buildTimestamp
  DiceRollState.onFace.index, 0, 100, 0,
];

// Minimal DieDomain subclass for direct method testing.
class _TestDieDomain extends DieDomain {
  _TestDieDomain() : super(TestBleRepository(), HaRepositoryEmpty());
}

// DieDomain with a real AppService for persistence-restore tests.
class _TestDieDomainWithService extends DieDomain {
  _TestDieDomainWithService(InMemoryAppService service)
      : super(TestBleRepository(), HaRepositoryEmpty(), service);
}

Future<PixelDie> _makePixelDie(MockBleDeviceWrapper device) async {
  final ctrl = StreamController<List<int>>.broadcast(sync: true);
  when(() => device.deviceId).thenReturn('pixel-test-id');
  when(() => device.friendlyName).thenReturn('Test Pixel');
  when(() => device.servicesUuids).thenReturn([pix.pixelsService]);
  when(() => device.characteristicUuids).thenReturn([
    pix.pixelWriteCharacteristic,
    pix.pixelNotifyCharacteristic,
  ]);
  when(() => device.init()).thenAnswer((_) async => true);
  when(() => device.notifyStream).thenAnswer((_) => ctrl.stream);
  when(() => device.setDeviceUuids(
        serviceUuid: any(named: 'serviceUuid'),
        notifyUuid: any(named: 'notifyUuid'),
        writeUuid: any(named: 'writeUuid'),
      )).thenAnswer((_) async {});
  when(() => device.writeMessage(any())).thenAnswer((invocation) async {
    final data = invocation.positionalArguments[0] as List<int>;
    if (data.isNotEmpty && data[0] == pix.PixelMessageType.whoAreYou.index) {
      ctrl.add(_buildTestIAmADie());
    }
  });
  return PixelDie.create(device: device);
}

void main() {
  setupLogger(Level.WARNING);

  late MockBleDeviceWrapper mockDevice;
  late _TestDieDomain domain;
  late PixelDie pixelDie;

  setUp(() async {
    mockDevice = MockBleDeviceWrapper();
    domain = _TestDieDomain();
    pixelDie = await _makePixelDie(mockDevice);
    // clear the whoAreYou init write so counts are clean
    clearInteractions(mockDevice);
  });

  // ── stopAnimations ──────────────────────────────────────────────────────────

  group('stopAnimations', () {
    test('sends MessageStopAllAnimations to Pixels die', () async {
      await domain.stopAnimations(pixelDie);

      final captured = verify(() => mockDevice.writeMessage(captureAny())).captured;
      expect(captured, hasLength(1));
      final buf = captured.first as List<int>;
      expect(buf, equals([pix.PixelMessageType.stopAllAnimations.index]));
    });

    test('no-op for VirtualDie', () async {
      final vDie = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d6'));
      await domain.stopAnimations(vDie);
      verifyNever(() => mockDevice.writeMessage(any()));
    });
  });

  // ── setDieName (true BLE rename) ─────────────────────────────────────────────

  group('setDieName', () {
    test('sends MessageSetName with the encoded name to Pixels die', () async {
      await domain.setDieName(pixelDie, 'Sparkle');

      final captured = verify(() => mockDevice.writeMessage(captureAny())).captured;
      expect(captured, hasLength(1));
      final buf = captured.first as List<int>;
      expect(buf[0], equals(pix.PixelMessageType.setName.index));
      // Name bytes follow the type byte; buffer is padded to maxNameBytes + 1.
      expect(buf.sublist(1, 1 + 'Sparkle'.length), equals('Sparkle'.codeUnits));
      expect(buf.length, equals(1 + pix.MessageSetName.maxNameBytes + 1));
    });

    test('no-op for VirtualDie', () async {
      final vDie = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d6'));
      await domain.setDieName(vDie, 'Sparkle');
      verifyNever(() => mockDevice.writeMessage(any()));
    });
  });

  // ── friendlyName override (rename reflects locally) ──────────────────────────

  group('friendlyName override', () {
    test('defaults to the BLE-advertised name', () {
      expect(pixelDie.friendlyName, equals('Test Pixel'));
    });

    test('setter overrides the advertised name', () {
      pixelDie.friendlyName = 'Sparkle';
      expect(pixelDie.friendlyName, equals('Sparkle'));
    });
  });

  // ── blinkRolling ────────────────────────────────────────────────────────────

  group('blinkRolling', () {
    test('no-op when rollingFlashEnabled is false', () async {
      pixelDie.rollingFlashEnabled = false;
      await domain.blinkRolling(pixelDie);
      verifyNever(() => mockDevice.writeMessage(any()));
    });

    test('sends MessageBlink with loopCount 255 when enabled', () async {
      pixelDie.rollingFlashEnabled = true;
      pixelDie.rollingFlashColor = Colors.red;
      pixelDie.rollingFlashPreset = RollingFlashPreset.strobe;

      await domain.blinkRolling(pixelDie);

      final captured = verify(() => mockDevice.writeMessage(captureAny())).captured;
      expect(captured, hasLength(1));
      final buf = captured.first as List<int>;
      expect(buf[0], equals(pix.PixelMessageType.blink.index));
      expect(buf[13], equals(255)); // loopCount
    });

    test('Strobe preset uses 50ms duration', () async {
      pixelDie.rollingFlashEnabled = true;
      pixelDie.rollingFlashPreset = RollingFlashPreset.strobe;

      await domain.blinkRolling(pixelDie);

      final buf = verify(() => mockDevice.writeMessage(captureAny())).captured.first as List<int>;
      // MessageBlink duration is stored little-endian in bytes 2-3
      final duration = buf[2] | (buf[3] << 8);
      expect(duration, equals(50));
    });

    test('Pulse preset uses 400ms duration', () async {
      pixelDie.rollingFlashEnabled = true;
      pixelDie.rollingFlashPreset = RollingFlashPreset.pulse;

      await domain.blinkRolling(pixelDie);

      final buf = verify(() => mockDevice.writeMessage(captureAny())).captured.first as List<int>;
      final duration = buf[2] | (buf[3] << 8);
      expect(duration, equals(400));
    });

    test('Breathe preset uses 600ms duration and fade=128', () async {
      pixelDie.rollingFlashEnabled = true;
      pixelDie.rollingFlashPreset = RollingFlashPreset.breathe;

      await domain.blinkRolling(pixelDie);

      final buf = verify(() => mockDevice.writeMessage(captureAny())).captured.first as List<int>;
      final duration = buf[2] | (buf[3] << 8);
      expect(duration, equals(600));
      expect(buf[12], equals(128)); // fade byte
    });

    test('no-op for VirtualDie', () async {
      final vDie = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d6'));
      vDie.rollingFlashEnabled = true;
      await domain.blinkRolling(vDie);
      verifyNever(() => mockDevice.writeMessage(any()));
    });
  });

  // ── removeAllVirtualDice ────────────────────────────────────────────────────

  group('removeAllVirtualDice', () {
    test('removes all virtual dice from domain', () {
      domain.addVirtualDie(faceCount: 6);
      domain.addVirtualDie(faceCount: 20);
      expect(domain.dieCount, equals(2));

      domain.removeAllVirtualDice();

      expect(domain.dieCount, equals(0));
    });

    test('does not remove BLE dice', () async {
      await domain.asyncConvertToDie({'pixel-test-id': mockDevice});
      domain.addVirtualDie(faceCount: 6);
      expect(domain.dieCount, equals(2));

      domain.removeAllVirtualDice();

      expect(domain.dieCount, equals(1));
      expect(domain.getDieById('pixel-test-id'), isNotNull);
    });

    test('emits updated stream with virtual dice removed', () async {
      domain.addVirtualDie(faceCount: 6);

      // Listen before triggering the removal.
      final emitted = domain.getDiceStream().first;
      domain.removeAllVirtualDice();

      final result = await emitted;
      expect(result, isEmpty);
    });
  });

  // ── Persistence restore ─────────────────────────────────────────────────────

  group('persistence restore on connect', () {
    late InMemoryAppService service;
    late _TestDieDomainWithService domainWithService;

    setUp(() {
      service = InMemoryAppService();
      domainWithService = _TestDieDomainWithService(service);
    });

    test('restores rollingFlashEnabled from saved settings', () async {
      await service.saveDieSettings('pixel-test-id', DieSettings(
        rollingFlashEnabled: true,
      ));

      await domainWithService.asyncConvertToDie({'pixel-test-id': mockDevice});

      final die = domainWithService.getDieById('pixel-test-id');
      expect(die, isNotNull);
      expect(die!.rollingFlashEnabled, isTrue);
    });

    test('restores rollingFlashColor from saved settings', () async {
      await service.saveDieSettings('pixel-test-id', DieSettings(
        rollingFlashColor: Colors.green,
      ));

      await domainWithService.asyncConvertToDie({'pixel-test-id': mockDevice});

      final die = domainWithService.getDieById('pixel-test-id');
      expect(die!.rollingFlashColor?.toARGB32(), equals(Colors.green.toARGB32()));
    });

    test('restores rollingFlashPreset from saved settings', () async {
      await service.saveDieSettings('pixel-test-id', DieSettings(
        rollingFlashPreset: RollingFlashPreset.breathe,
      ));

      await domainWithService.asyncConvertToDie({'pixel-test-id': mockDevice});

      final die = domainWithService.getDieById('pixel-test-id');
      expect(die!.rollingFlashPreset, equals(RollingFlashPreset.breathe));
    });

    test('die with no saved settings keeps defaults', () async {
      // No entry saved for this die.
      await domainWithService.asyncConvertToDie({'pixel-test-id': mockDevice});

      final die = domainWithService.getDieById('pixel-test-id');
      expect(die, isNotNull);
      expect(die!.rollingFlashEnabled, isFalse);
      expect(die.rollingFlashColor, isNull);
      expect(die.rollingFlashPreset, equals(RollingFlashPreset.strobe));
    });
  });
}
