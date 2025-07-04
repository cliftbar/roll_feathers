import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
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
    when(() => mockDevice.servicesUuids).thenReturn([pix.pixelsService]);
    when(() => mockDevice.characteristicUuids).thenReturn([
      pix.pixelWriteCharacteristic,
      pix.pixelNotifyCharacteristic
    ]);
    when(() => mockDevice.init()).thenAnswer((_) async => true);
    when(() => mockDevice.notifyStream).thenAnswer((_) => notifyStreamController.stream);
    when(() => mockDevice.setDeviceUuids(
      serviceUuid: any(named: 'serviceUuid'),
      notifyUuid: any(named: 'notifyUuid'),
      writeUuid: any(named: 'writeUuid')
    )).thenAnswer((_) async {});
    when(() => mockDevice.writeMessage(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    notifyStreamController.close();
  });

  // Test constructor and initialization
  test('PixelDie constructor initializes with correct values', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);

    expect(die.type, equals(GenericDieType.pixel));
    expect(die.dieId, equals('test-device-id'));
    expect(die.friendlyName, equals('Test Device'));
  });

  // Test initialization
  test('PixelDie initialization sets up device and sends initial message', () async {
    await PixelDie.create(device: mockDevice);

    verify(() => mockDevice.setDeviceUuids(
      serviceUuid: pix.pixelsService,
      notifyUuid: pix.pixelNotifyCharacteristic,
      writeUuid: pix.pixelWriteCharacteristic
    )).called(1);

    // Verify that the WhoAreYou message was sent
    verify(() => mockDevice.writeMessage(any())).called(1);
  });

  // Test handling of iAmADie message
  test('PixelDie handles iAmADie message correctly', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);

    // Create a mock iAmADie message
    final mockIAmADieData = [
      pix.PixelMessageType.iAmADie.index, // message type
      20, // ledCount
      pix.PixelDesignAndColor.onyxBlack.index, // designAndColor
      pix.PixelDieType.d20.index, // pixelDieTypeFaces
      1, 0, 0, 0, // dataSetHash (4 bytes)
      2, 0, 0, 0, // pixelId (4 bytes)
      3, 0, // availableFlash (2 bytes)
      4, 0, 0, 0, // buildTimestamp (4 bytes)
      DiceRollState.rolled.index, // rollState
      5, // currentFaceIndex
      75, // batteryLevel
      BatteryState.ok.index, // batteryState
    ];

    notifyStreamController.add(mockIAmADieData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));

    // Verify the state was updated correctly
    expect(die.state.rollState, equals(DiceRollState.rolled.index));
    expect(die.state.currentFaceIndex, equals(5));
    expect(die.state.currentFaceValue, equals(6)); // currentFaceIndex + 1
    expect(die.state.batteryLevel, equals(75));
    expect(die.state.batteryState, equals(BatteryState.ok));

    // Verify the info was updated correctly
    expect(die.info?.ledCount, equals(20));
    expect(die.info?.designAndColor, equals(pix.PixelDesignAndColor.onyxBlack));
    expect(die.info?.pixelDieTypeFaces, equals(pix.PixelDieType.d20));
  });

  // Test handling of batteryLevel message
  test('PixelDie handles batteryLevel message correctly', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);

    // Create a mock batteryLevel message
    final mockBatteryLevelData = [
      pix.PixelMessageType.batteryLevel.index, // message type
      80, // batteryLevel
      BatteryState.ok.index, // batteryState
    ];

    notifyStreamController.add(mockBatteryLevelData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));

    // Verify the state was updated correctly
    expect(die.state.batteryLevel, equals(80));
    expect(die.state.batteryState, equals(BatteryState.ok));
  });

  // Test handling of rollState message
  test('PixelDie handles rollState message correctly', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);
    bool callbackCalled = false;

    die.addRollCallback(DiceRollState.rolled, "testCallback", (state) {
      callbackCalled = true;
    });

    // Create a mock rollState message for a rolled die
    final mockRollStateData = [
      pix.PixelMessageType.rollState.index, // message type
      DiceRollState.rolled.index, // rollState
      7, // currentFaceIndex
    ];

    notifyStreamController.add(mockRollStateData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));

    // Verify the state was updated correctly
    expect(die.state.rollState, equals(DiceRollState.rolled.index));
    expect(die.state.currentFaceIndex, equals(7));
    expect(die.state.currentFaceValue, equals(8)); // currentFaceIndex + 1
    expect(die.state.lastRolled, isNotNull);
    expect(callbackCalled, isTrue);
  });

  // Test handling of unknown message type
  test('PixelDie handles unknown message type correctly', () async {
    await PixelDie.create(device: mockDevice);

    // Create a mock message with an unknown type
    final mockUnknownData = [
      pix.PixelMessageType.none.index, // message type
      1, 2, 3, 4, // some random data
    ];

    // This should not throw an exception
    notifyStreamController.add(mockUnknownData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));
  });

  // Test dType getter
  test('dType getter returns correct value', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);

    // Initially, without info, it should return unknown
    expect(die.dType.name, equals('unknown'));

    // Create a mock iAmADie message with d20 type
    final mockIAmADieData = [
      pix.PixelMessageType.iAmADie.index, // message type
      20, // ledCount
      pix.PixelDesignAndColor.onyxBlack.index, // designAndColor
      pix.PixelDieType.d20.index, // pixelDieTypeFaces
      1, 0, 0, 0, // dataSetHash (4 bytes)
      2, 0, 0, 0, // pixelId (4 bytes)
      3, 0, // availableFlash (2 bytes)
      4, 0, 0, 0, // buildTimestamp (4 bytes)
      DiceRollState.rolled.index, // rollState
      5, // currentFaceIndex
      75, // batteryLevel
      BatteryState.ok.index, // batteryState
    ];

    notifyStreamController.add(mockIAmADieData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));

    // Now it should return d20
    expect(die.dType.name, equals('d20'));
    expect(die.dType.faces, equals(20));
  });

  // Test dType setter (which throws UnsupportedError)
  test('dType setter throws UnsupportedError', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);

    expect(() => die.dType = GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6),
        throwsA(isA<UnsupportedError>()));
  });

  // Test blinkColor getter and setter
  test('blinkColor getter and setter work correctly', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);

    // Initial blinkColor should be null
    expect(die.blinkColor, isNull);

    // Set blinkColor to red
    die.blinkColor = Colors.red;

    // Verify blinkColor changed
    expect(die.blinkColor, equals(Colors.red));
  });

  // Test message callbacks
  test('addMessageCallback registers and triggers callback correctly', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);
    bool callbackCalled = false;

    die.addMessageCallback(pix.PixelMessageType.batteryLevel.index, "testCallback", (msg) {
      callbackCalled = true;
    });

    // Create a mock batteryLevel message
    final mockBatteryLevelData = [
      pix.PixelMessageType.batteryLevel.index, // message type
      80, // batteryLevel
      BatteryState.ok.index, // batteryState
    ];

    notifyStreamController.add(mockBatteryLevelData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));

    expect(callbackCalled, isTrue);
  });

  // Test roll callbacks
  test('addRollCallback registers and triggers callback correctly', () async {
    final PixelDie die = await PixelDie.create(device: mockDevice);
    bool callbackCalled = false;

    die.addRollCallback(DiceRollState.rolling, "testCallback", (state) {
      callbackCalled = true;
    });

    // Create a mock rollState message for a rolling die
    final mockRollStateData = [
      pix.PixelMessageType.rollState.index, // message type
      DiceRollState.rolling.index, // rollState
      0, // currentFaceIndex
    ];

    notifyStreamController.add(mockRollStateData);

    // Wait for the message to be processed
    await Future.delayed(Duration(milliseconds: 10));

    expect(callbackCalled, isTrue);
  });
}
