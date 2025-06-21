import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_repository.dart';

class UniversalBleDevice implements BleDeviceWrapper {
  @override
  Logger log = Logger("UniversalBleDevice");

  @override
  @override
  String get deviceId => device.deviceId;

  @override
  List<String> get servicesUuids => _services.map((s) => s.uuid).toList();

  @override
  List<String> get characteristicUuids => _characteristics.map((c) => c.uuid).toList();

  @override
  bool initialized = false;
  BleDevice device;
  List<BleService> _services = [];
  List<BleCharacteristic> _characteristics = [];

  String? _serviceId;
  String? _writeCharacteristicId;
  String? _notifyCharacteristicId;

  UniversalBleDevice({required this.device});

  @override
  Future<bool> init() async {
    _services = await UniversalBle.discoverServices(deviceId);
    log.fine("service length: ${_services.length}");
    _characteristics = _services.expand((s) => s.characteristics).toList();

    return initialized;
  }

  @override
  Future<void> discoverServices() async {
    var servics = await UniversalBle.discoverServices(deviceId);
    log.fine("discoverServices ${servics.length} $servics");
  }

  @override
  Future<void> setDeviceUuids({
    required String serviceUuid,
    required String notifyUuid,
    required String writeUuid,
  }) async {
    _serviceId = serviceUuid;
    _notifyCharacteristicId = notifyUuid;
    _writeCharacteristicId = writeUuid;
    await UniversalBle.setNotifiable(deviceId, serviceUuid, notifyUuid, BleInputProperty.notification);
  }

  @override
  Future<void> writeMessage(List<int> data) async {
    UniversalBle.writeValue(
      deviceId,
      _serviceId!,
      _writeCharacteristicId!,
      Uint8List.fromList(data),
      BleOutputProperty.withoutResponse,
    );
  }

  @override
  Stream<List<int>> get notifyStream => UniversalBle.characteristicValueStream(deviceId, _notifyCharacteristicId!);

  @override
  Future<void> disconnect() async {
    await UniversalBle.disconnect(deviceId);
  }

  @override
  String get friendlyName => device.name ?? deviceId;
}

class BleUniversalRepository implements BleRepository {
  final _log = Logger("BleUniversalRepository");

  final Map<String, UniversalBleDevice> _discoveredBleDevices = {};

  @override
  Map<String, BleDeviceWrapper> get discoveredBleDevices => _discoveredBleDevices;
  final _bleDeviceSubscription = StreamController<Map<String, BleDeviceWrapper>>.broadcast();
  final _bleEnabledSubscription = StreamController<bool>.broadcast();
  @override
  bool enabled = false;
  @override
  bool supported = false;
  bool permissioned = false;

  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => _bleDeviceSubscription.stream;

  @override
  Stream<bool> subscribeBleEnabled() => _bleEnabledSubscription.stream;

  late StreamSubscription<AvailabilityState> _adapterStateStateSubscription;

  @override
  Future<void> init() async {
    await _connect();

    UniversalBle.timeout = const Duration(seconds: 10);
    supported = await isSupported();
    if (!supported) {
      _log.severe("Bluetooth is not supported");
    }
    if (Platform.isAndroid || Platform.isIOS) {
      Map<Permission, PermissionStatus> statuses = await [
        // Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (!statuses.values.any((t) => t != PermissionStatus.granted)) {
        permissioned = true;
      }
    } else {
      permissioned = true;
    }

    _bleEnabledSubscription.add(enabled && supported && permissioned);

    _log.info("ble_repo initialized");
  }

  @override
  Future<bool> isSupported() async {
    return supported;
  }

  Future<void> _connect({Duration timeout = const Duration(seconds: 3)}) async {
    _adapterStateStateSubscription = UniversalBle.availabilityStream.listen((state) {
      if (state == AvailabilityState.unsupported ||
          state == AvailabilityState.unknown ||
          state == AvailabilityState.unauthorized) {
        supported = false;
        enabled = false;
        _bleEnabledSubscription.add(enabled && supported && permissioned);
      } else if (state == AvailabilityState.poweredOn) {
        supported = true;
        enabled = true;
        _bleEnabledSubscription.add(enabled && supported && permissioned);
      }
    });
    await UniversalBle.availabilityStream
        .firstWhere(
          (state) => state == AvailabilityState.poweredOn,
          orElse: () => throw TimeoutException('Bluetooth did not turn on'),
        )
        .timeout(timeout, onTimeout: () => throw TimeoutException('Bluetooth enablement timeout after 10 seconds'));
  }

  final Map<String, int> _deviceReconnects = {};

  @override
  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)}) async {
    if (!supported || !enabled) {
      return;
    }
    _log.info("ble scan start");
    var scanSub = UniversalBle.scanStream.listen((BleDevice bleDevice) async {
      await UniversalBle.connect(bleDevice.deviceId);
      UniversalBle.connectionStream(bleDevice.deviceId).listen((bool isConnected) async {
        if (!isConnected) {
          if (_discoveredBleDevices.containsKey(bleDevice.deviceId)) {
            // not manually disconnected, try reconnect
            int reconnects = _deviceReconnects.putIfAbsent(bleDevice.deviceId, () => 0);
            if (reconnects < 0) {
              //attempt reconnect, but disabled for now
              await Future.delayed(Duration(seconds: 1 * reconnects));
              await UniversalBle.connect(bleDevice.deviceId);
              _log.warning("attempting reconnect on ${bleDevice.deviceId} ${await bleDevice.connectionState}");
              _discoveredBleDevices[bleDevice.deviceId] = UniversalBleDevice(device: bleDevice);
            } else {
              _log.warning("disconnecting ${bleDevice.deviceId} ${await bleDevice.connectionState}");
              _discoveredBleDevices.remove(bleDevice.deviceId);
            }
          }
          _bleDeviceSubscription.add(_discoveredBleDevices);
        }
      });
      _discoveredBleDevices[bleDevice.deviceId] = UniversalBleDevice(device: bleDevice);
      _bleDeviceSubscription.add(_discoveredBleDevices);
    });

    // Start scanning
    await UniversalBle.startScan(scanFilter: ScanFilter(withServices: services ?? []));

    Timer(Duration(seconds: 10), () {
      UniversalBle.stopScan();
      scanSub.cancel();
      _log.info("Scan finished");
    });
  }

  // Stop scanning for devices
  @override
  Future<void> stopScan() async {
    await UniversalBle.stopScan();
  }

  // Disconnect a specific device
  @override
  Future<void> disconnectDevice(String deviceId) async {
    await UniversalBle.disconnect(deviceId);
    if (_discoveredBleDevices.containsKey(deviceId)) {

      _discoveredBleDevices.remove(deviceId);
    }
    _bleDeviceSubscription.add(_discoveredBleDevices);
  }

  // Disconnect all devices
  @override
  Future<void> disconnectAllDevices() async {
    for (BleDeviceWrapper device in List.of(_discoveredBleDevices.values)) {
      await UniversalBle.disconnect(device.deviceId);
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
