import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart' as godice;
import 'package:roll_feathers/repositories/ble/ble_repository.dart';

import 'test_util.dart';

// Mock classes
class MockBleDeviceWrapper extends Mock implements BleDeviceWrapper {}

void main() {
  setupLogger(Level.FINE);

  late MockBleDeviceWrapper mockDevice;
  late StreamController<List<int>> notifyStreamController;

  setUp(() {
    mockDevice = MockBleDeviceWrapper();
    notifyStreamController = StreamController<List<int>>.broadcast(sync: true);

    // Setup mock device
    when(() => mockDevice.deviceId).thenReturn('test-device-id');
    when(() => mockDevice.friendlyName).thenReturn('Test Device');
    when(() => mockDevice.servicesUuids).thenReturn([godice.godiceServiceGuid]);
    when(
      () => mockDevice.characteristicUuids,
    ).thenReturn([godice.godiceWriteCharacteristic, godice.godiceNotifyCharacteristic]);
    when(() => mockDevice.init()).thenAnswer((_) async => true);
    when(() => mockDevice.notifyStream).thenAnswer((_) => notifyStreamController.stream);
    when(
      () => mockDevice.setDeviceUuids(
        serviceUuid: any(named: 'serviceUuid'),
        notifyUuid: any(named: 'notifyUuid'),
        writeUuid: any(named: 'writeUuid'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockDevice.writeMessage(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    notifyStreamController.close();
  });

  // Test constructor and initialization
  test('GoDiceBle constructor initializes with correct values', () {
    // Test that the constructor initializes the object with the correct values
    final die = GoDiceBle(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);

    expect(die.type, equals(GenericDieType.godice));
    expect(die.dieId, equals('test-device-id'));
    expect(die.dType.name, equals('d6'));
    expect(die.dType.faces, equals(6));
  });

  // Test initialization method
  test('GoDiceBle _init method sets up device and sends initial messages', () async {
    // Test that the _init method sets up the device and sends initial messages
    await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);

    verify(
      () => mockDevice.setDeviceUuids(
        serviceUuid: godice.godiceServiceGuid,
        notifyUuid: godice.godiceNotifyCharacteristic,
        writeUuid: godice.godiceWriteCharacteristic,
      ),
    ).called(1);

    verify(() => mockDevice.writeMessage(any())).called(2);
  });

  // Test getClosestRollByVector method
  test('getClosestRollByVector returns correct value for d6', () {
    // Test that getClosestRollByVector returns the correct value for a d6 die
    final die = GoDiceBle(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);

    // Test with vector for face 1 (should return 1)
    final vector1 = godice.Vector(x: -64, y: 0, z: 0);
    expect(die.getClosestRollByVector(vector1, godice.GodiceDieType.d6), equals(1));

    // Test with vector for face 6 (should return 6)
    final vector6 = godice.Vector(x: 64, y: 0, z: 0);
    expect(die.getClosestRollByVector(vector6, godice.GodiceDieType.d6), equals(6));

    // Test with a vector that's close to face 3 (should return 3)
    final vector3 = godice.Vector(x: 0, y: 63, z: 0);
    expect(die.getClosestRollByVector(vector3, godice.GodiceDieType.d6), equals(3));
  });

  group('d6 Roll message updates state correctly: ', () {
    for (var element in godice.vectors[godice.GodiceDieType.d6]!.entries) {
      // Test _handleRollUpdate method
      test('Roll message updates state correctly face ${element.key}:', () async {
        // Test that _handleRollUpdate updates the state correctly, via

        final godice.Vector vector = element.value;
        final GoDiceBle die = await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);
        notifyStreamController.add(godice.MessageStable.dataToBuffer(vector));

        // Test with vector for face 4
        expect(die.state.rollState, equals(DiceRollState.rolled.index));
        expect(die.state.currentFaceIndex, equals(element.key - 1)); // 0-based index for face 4
        expect(die.state.currentFaceValue, equals(element.key));
        expect(die.state.lastRolled, isNotNull);
      });
    }
  });

  // Test _readNotify method with batteryLevelAck message
  test('_readNotify handles batteryLevelAck message correctly', () async {
    final int batteryLevel = 75;
    // Test that _readNotify handles a batteryLevelAck message correctly
    final GoDiceBle die = await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);

    // Create a batteryLevelAck message with 75% battery
    notifyStreamController.add(godice.MessageBatteryLevelAck.dataToBuffer(batteryLevel));

    expect(die.state.batteryLevel, equals(75));
    expect(die.state.batteryState, equals(BatteryState.ok));
  });

  // Test _readNotify method with diceColorAck message
  test('_readNotify handles diceColorAck message correctly', () async {
    // Test that _readNotify handles a diceColorAck message correctly
    final GoDiceBle die = await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);
    // Create a diceColorAck message with color red (index 1)
    notifyStreamController.add(godice.MessageDiceColorAck.dataToBuffer(godice.GodiceDieColor.red));

    expect(die.info["diceColor"], equals("red"));
    expect(die.friendlyName, equals("GoDice red"));
  });

  // Test _readNotify method with stable message
  test('_readNotify handles stable message correctly', () async {
    // Test that _readNotify handles a stable message correctly
    final GoDiceBle die = await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);
    bool callbackCalled = false;
    die.addRollCallback(DiceRollState.rolled, "testCallback", (state) {
      callbackCalled = true;
    });
    // Create a stable message with vector for face 5
    notifyStreamController.add(godice.MessageTiltStable.dataToBuffer(godice.vectors[godice.GodiceDieType.d6]![5]!));

    expect(die.state.currentFaceValue, equals(5));
    expect(callbackCalled, isTrue);
  });

  // Test _readNotify method with rollStart message
  test('_readNotify handles rollStart message correctly', () async {
    // Test that _readNotify handles a rollStart message correctly
    final GoDiceBle die = await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);
    bool callbackCalled = false;
    die.addRollCallback(DiceRollState.rolling, "testCallback", (state) {
      callbackCalled = true;
    });

    notifyStreamController.add(godice.MessageRollStart.dataToBuffer());
    expect(die.state.rollState, equals(DiceRollState.rolling.index));
    expect(callbackCalled, isTrue);
  });

  // Test dType getter and setter
  test('dType getter and setter work correctly', () {
    // Test that the dType getter and setter work correctly
    final die = GoDiceBle(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);

    // Initial type should be d6
    expect(die.dType.name, equals('d6'));

    // Change to d20
    die.dType = GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20);

    // Verify type changed
    expect(die.dType.name, equals('d20'));
    expect(die.info["dieFaceType"], equals(godice.GodiceDieType.d20));
  });

  // Test blinkColor getter and setter
  test('blinkColor getter and setter work correctly', () {
    // Test that the blinkColor getter and setter work correctly
    final die = GoDiceBle(dieFaceType: godice.GodiceDieType.d6, device: mockDevice);

    // Initial blinkColor should be null
    expect(die.blinkColor, isNull);

    // Set blinkColor to red
    die.blinkColor = Colors.red;

    // Verify blinkColor changed
    expect(die.blinkColor, equals(Colors.red));
  });
}
