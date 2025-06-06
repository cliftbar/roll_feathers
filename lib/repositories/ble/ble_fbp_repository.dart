import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import 'ble_repository.dart';

class FbpBleDevice implements BleDeviceWrapper {
  @override
  bool initialized = false;

  @override
  Logger log = Logger("FbpBleDevice");

  @override
  String get deviceId => device.remoteId.str;

  BluetoothDevice device;

  BluetoothService? _service;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  FbpBleDevice({required this.device});

  @override
  Future<bool> init() async {
    await discoverServices();

    return initialized;
  }

  @override
  Future<void> discoverServices() async {
    await device.discoverServices();
  }

  @override
  // TODO: implement notifyStream
  Stream<List<int>> get notifyStream => _notifyCharacteristic!.onValueReceived;

  @override
  List<String> get characteristicUuids =>
      device.servicesList.expand((s) => s.characteristics).map((c) => c.uuid.str).toList();
  @override
  List<String> get servicesUuids => device.servicesList.map((s) => s.serviceUuid.str).toList();

  @override
  Future<void> setDeviceUuids({
    required String serviceUuid,
    required String notifyUuid,
    required String writeUuid,
  }) async {
    _service = device.servicesList.firstWhere((bs) => bs.serviceUuid.str == serviceUuid);
    _notifyCharacteristic = _service?.characteristics.firstWhere((c) => c.uuid.str == notifyUuid);
    _writeCharacteristic = _service?.characteristics.firstWhere((c) => c.uuid.str == writeUuid);
    await _notifyCharacteristic?.setNotifyValue(true);
  }

  @override
  Future<void> writeMessage(List<int> data) async {
    _writeCharacteristic?.write(data);
  }

  @override
  Future<void> disconnect() async {
    await device.disconnect();
  }

  @override
  // TODO: implement friendlyName
  String get friendlyName => device.platformName;
}

class BleFbpCrossRepository implements BleRepository {
  final _log = Logger("BleRepository");

  final Map<String, FbpBleDevice> _discoveredBleDevices = {};
  @override
  Map<String, BleDeviceWrapper> get discoveredBleDevices => _discoveredBleDevices;
  final _bleDeviceSubscription = StreamController<Map<String, FbpBleDevice>>.broadcast();
  final _bleEnabledSubscription = StreamController<bool>.broadcast();
  @override
  bool enabled = false;
  @override
  bool supported = false;

  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => _bleDeviceSubscription.stream;
  @override
  Stream<bool> subscribeBleEnabled() => _bleEnabledSubscription.stream;

  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

  @override
  Future<void> init() async {
    supported = await isSupported();
    if (!supported) {
      _log.severe("Bluetooth is not supported");
    }

    await _connect();

    _bleEnabledSubscription.add(enabled && supported);

    _log.info("ble_repo initialized");
  }

  @override
  Future<bool> isSupported() async {
    return await FlutterBluePlus.isSupported;
  }

  Future<void> _connect({Duration timeout = const Duration(seconds: 3)}) async {
    if (!supported) {
      return;
    }
    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((BluetoothAdapterState? state) {
      if (state == BluetoothAdapterState.on) {
        enabled = true;
        _bleEnabledSubscription.add(enabled && supported);
      } else {
        enabled = false;
        _bleEnabledSubscription.add(enabled && supported);
      }
    });
    await FlutterBluePlus.adapterState
        .firstWhere(
          (state) => state == BluetoothAdapterState.on,
          orElse: () => throw TimeoutException('Bluetooth did not turn on'),
        )
        .timeout(timeout, onTimeout: () => throw TimeoutException('Bluetooth connection timeout after 10 seconds'));
  }

  @override
  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)}) async {
    if (!supported || !enabled) {
      return;
    }
    _log.info("ble scan start");
    var scanSub = FlutterBluePlus.onScanResults.listen((srs) async {
      for (var sr in srs) {
        await sr.device.connect();
        sr.device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
            _discoveredBleDevices.remove(sr.device.remoteId.str);
            _bleDeviceSubscription.add(_discoveredBleDevices);
          }
        });
        _discoveredBleDevices[sr.device.remoteId.str] = FbpBleDevice(device: sr.device);
      }

      _bleDeviceSubscription.add(_discoveredBleDevices);
    });

    FlutterBluePlus.cancelWhenScanComplete(scanSub);

    // Start scanning
    await FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: services?.map((e) => Guid(e)).toList() ?? [], // Filter by service UUID (optional)
    );
  }

  // Stop scanning for devices
  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
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
    _adapterStateStateSubscription.cancel();
    _bleDeviceSubscription.close();
    _bleEnabledSubscription.close();
  }
}
