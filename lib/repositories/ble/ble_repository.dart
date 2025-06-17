import 'dart:async';

import 'package:logging/logging.dart';

class BluetoothNotSupported implements Exception {
  BluetoothNotSupported();
}

abstract class BleDeviceWrapper {
  abstract bool initialized;
  abstract Logger log;

  String get deviceId;

  String get friendlyName;

  List<String> get servicesUuids;

  List<String> get characteristicUuids;

  Future<bool> init();

  Future<void> discoverServices();

  Future<void> setDeviceUuids({required String serviceUuid, required String notifyUuid, required String writeUuid});

  Future<void> writeMessage(List<int> data);

  Stream<List<int>> get notifyStream;

  Future<void> disconnect();
}

abstract class BleRepository {
  Map<String, BleDeviceWrapper> get discoveredBleDevices;

  bool enabled = false;
  bool supported = false;

  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices();

  Stream<bool> subscribeBleEnabled();

  Future<void> init();

  Future<bool> isSupported();

  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)});

  // Stop scanning for devices
  Future<void> stopScan();

  // Disconnect a specific device
  Future<void> disconnectDevice(String deviceId);

  // Disconnect all devices
  Future<void> disconnectAllDevices();

  void dispose();
}
