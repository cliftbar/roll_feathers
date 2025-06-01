import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:logging/logging.dart';

class BluetoothNotSupported extends fbp.FlutterBluePlusException {
  BluetoothNotSupported(super.platform, super.function, super.code, super.description);
}

class BleRepository {
  final _log = Logger("BleRepository");

  final Map<String, fbp.BluetoothDevice> _discoveredBleDevices = {};
  Map<String, fbp.BluetoothDevice> get discoveredBleDevices => _discoveredBleDevices;
  final _bleDeviceSubscription = StreamController<Map<String, fbp.BluetoothDevice>>.broadcast();
  bool initialized = false;

  Stream<Map<String, fbp.BluetoothDevice>> subscribeBleDevices() => _bleDeviceSubscription.stream;

  Future<void> init() async {
    bool supported = await isSupported();
    if (!supported) {
      throw BluetoothNotSupported(fbp.ErrorPlatform.fbp, "_initializeBle()", -1, "Bluetooth is not supported");
    }

    await connect();

    _log.info("ble_repo initialized");
  }

  Future<bool> isSupported() async {
    return fbp.FlutterBluePlus.isSupported;
  }

  Future<void> connect({Duration timeout = const Duration(seconds: 3)}) async {
    await fbp.FlutterBluePlus.adapterState
        .firstWhere(
          (state) => state == fbp.BluetoothAdapterState.on,
          orElse: () => throw TimeoutException('Bluetooth did not turn on'),
        )
        .timeout(timeout, onTimeout: () => throw TimeoutException('Bluetooth connection timeout after 10 seconds'));
    initialized = true;
  }

  Future<void> scan({List<fbp.Guid>? services, Duration? timeout = const Duration(seconds: 5)}) async {
    _log.info("ble scan start");
    var scanSub = fbp.FlutterBluePlus.onScanResults.listen((srs) async {
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
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  void dispose() {
    stopScan();
    _bleDeviceSubscription.close();
  }
}
