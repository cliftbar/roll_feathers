import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
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
    print(_services.length);
    _characteristics = _services.expand((s) => s.characteristics).toList();

    return initialized;
  }

  @override
  Future<void> discoverServices() async {
    var servics = await UniversalBle.discoverServices(deviceId);
    print("xcb ${servics.length} $servics");
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

  @override
  Stream<Map<String, BleDeviceWrapper>> subscribeBleDevices() => _bleDeviceSubscription.stream;
  @override
  Stream<bool> subscribeBleEnabled() => _bleEnabledSubscription.stream;

  late StreamSubscription<AvailabilityState> _adapterStateStateSubscription;

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
    return supported;
  }

  Future<void> _connect({Duration timeout = const Duration(seconds: 3)}) async {
    _adapterStateStateSubscription = UniversalBle.availabilityStream.listen((state) {
      if (state == AvailabilityState.unsupported ||
          state == AvailabilityState.unknown ||
          state == AvailabilityState.unauthorized) {
        supported = false;
        enabled = false;
        _bleEnabledSubscription.add(enabled && supported);
      } else if (state == AvailabilityState.poweredOn) {
        supported = true;
        enabled = true;
        _bleEnabledSubscription.add(enabled && supported);
      }
    });
    await UniversalBle.availabilityStream
        .firstWhere(
          (state) => state == AvailabilityState.poweredOn,
          orElse: () => throw TimeoutException('Bluetooth did not turn on'),
        )
        .timeout(timeout, onTimeout: () => throw TimeoutException('Bluetooth enablement timeout after 10 seconds'));
  }

  @override
  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)}) async {
    if (!supported || !enabled) {
      return;
    }
    _log.info("ble scan start");
    var scanSub = UniversalBle.scanStream.listen((BleDevice bleDevice) async {
      await UniversalBle.connect(bleDevice.deviceId);
      UniversalBle.connectionStream(bleDevice.deviceId).listen((bool isConnected) {
        if (!isConnected) {
          _discoveredBleDevices.remove(bleDevice.deviceId);
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
    if (_discoveredBleDevices.containsKey(deviceId)) {
      await UniversalBle.disconnect(deviceId);
      _discoveredBleDevices.remove(deviceId);
      _bleDeviceSubscription.add(_discoveredBleDevices);
    }
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
