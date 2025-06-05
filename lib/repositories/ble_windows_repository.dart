import 'dart:async';

import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart' as fbp;
// import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:logging/logging.dart';
import 'package:roll_feathers/repositories/ble_repository.dart';

class BleWindowsRepository implements BleRepository {
  final _log = Logger("BleRepository");

  final Map<String, fbp.BluetoothDevice> _discoveredBleDevices = {};
  @override
  Map<String, fbp.BluetoothDevice> get discoveredBleDevices => _discoveredBleDevices;
  final _bleDeviceSubscription = StreamController<Map<String, fbp.BluetoothDevice>>.broadcast();
  final _bleEnabledSubscription = StreamController<bool>.broadcast();
  @override
  bool initialized = false;
  @override
  bool supported = false;

  @override
  Stream<Map<String, fbp.BluetoothDevice>> subscribeBleDevices() => _bleDeviceSubscription.stream;
  @override
  Stream<bool> subscribeBleEnabled() => _bleEnabledSubscription.stream;

  @override
  Future<void> init() async {
    supported = await isSupported();
    if (!supported) {
      _log.severe("Bluetooth is not supported");
    }

    await _connect();

    _bleEnabledSubscription.add(initialized && supported);

    _log.info("ble_repo initialized");
  }

  @override
  Future<bool> isSupported() async {
    return await fbp.FlutterBluePlus.isSupported;
  }

  @override
  Future<void> _connect({Duration timeout = const Duration(seconds: 3)}) async {
    if (!supported) {
      return;
    }
    await fbp.FlutterBluePlus.adapterState
        .firstWhere(
          (state) => state == fbp.BluetoothAdapterState.on,
      orElse: () => throw TimeoutException('Bluetooth did not turn on'),
    )
        .then((isOn) => {initialized = isOn == fbp.BluetoothAdapterState.on})
        .timeout(timeout, onTimeout: () => throw TimeoutException('Bluetooth connection timeout after 10 seconds'));
  }

  @override
  Future<void> scan({List<fbp.Guid>? services, Duration? timeout = const Duration(seconds: 5)}) async {
    if (!supported) {
      return;
    }
    _log.info("ble scan start");
    var scanSub = fbp.FlutterBluePlus.scanResults.listen((srs) async {
      for (var sr in srs) {
        await sr.device.connect();
        sr.device.connectionState.listen((state) {
          if (state == fbp.BluetoothConnectionState.disconnected) {
            _discoveredBleDevices.remove(sr.device.remoteId.str);
            _bleDeviceSubscription.add(_discoveredBleDevices);
          }
        });
        _discoveredBleDevices[sr.device.remoteId.str] = sr.device;
      }

      _bleDeviceSubscription.add(_discoveredBleDevices);
    });

    fbp.FlutterBluePlus.cancelWhenScanComplete(scanSub);

    // Start scanning
    await fbp.FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: services ?? [], // Filter by service UUID (optional)
    );
  }

  // Stop scanning for devices
  @override
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  // Disconnect a specific device
  @override
  Future<void> disconnectDevice(String deviceId) async {
    if (_discoveredBleDevices.containsKey(deviceId)) {
      await _discoveredBleDevices[deviceId]!.disconnect();
      _discoveredBleDevices.remove(deviceId);
      _bleDeviceSubscription.add(_discoveredBleDevices);
    }
  }

  // Disconnect all devices
  @override
  Future<void> disconnectAllDevices() async {
    for (var device in List.of(_discoveredBleDevices.values)) {
      await device.disconnect();
    }
    _discoveredBleDevices.clear();
    _bleDeviceSubscription.add(_discoveredBleDevices);
  }

  @override
  void dispose() {
    stopScan();
    _bleDeviceSubscription.close();
    _bleEnabledSubscription.close();
  }
}