import 'package:flutter/foundation.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';

@visibleForTesting
class NoopBleRepository extends BleRepository {
  @override
  Map<String, BleDeviceWrapper> get discoveredBleDevices => {};
  @override
  void dispose() {}
  @override
  Future<void> disconnectAllDevices() async {}
  @override
  Future<void> disconnectDevice(String deviceId) async {}
  @override
  Future<void> init() async {}
  @override
  Future<bool> isSupported() async => false;
  @override
  Future<void> scan({List<String>? services, List<String>? namePrefix, Duration? timeout = const Duration(seconds: 5)}) async {}
  @override
  Stream<bool> subscribeBleEnabled() => const Stream.empty();
  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => const Stream.empty();
  @override
  Future<void> stopScan() async {}
}
