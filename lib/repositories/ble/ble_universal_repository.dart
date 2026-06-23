import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:roll_feathers/repositories/ble/ble_repository.dart';

class UniversalBleDevice implements BleDeviceWrapper {
  @override
  Logger log = Logger("UniversalBleDevice");

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

  final String? _cachedName;

  UniversalBleDevice({required this.device, String? cachedName}) : _cachedName = cachedName;

  /// Discover services and characteristics. Connection must already be established
  /// by [BleUniversalRepository] before calling this.
  @override
  Future<bool> init() async {
    _services = await UniversalBle.discoverServices(deviceId);
    log.fine("discovered ${_services.length} service(s)");
    _characteristics = _services.expand((s) => s.characteristics).toList();
    initialized = true;
    return initialized;
  }

  @override
  Future<void> discoverServices() async {
    _services = await UniversalBle.discoverServices(deviceId);
    _characteristics = _services.expand((s) => s.characteristics).toList();
    log.fine("discoverServices: ${_services.length} service(s)");
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
    await UniversalBle.subscribeNotifications(deviceId, serviceUuid, notifyUuid);
  }

  @override
  Future<void> writeMessage(List<int> data) async {
    if (_serviceId == null || _writeCharacteristicId == null) {
      throw StateError('setDeviceUuids must be called before writeMessage');
    }
    await UniversalBle.write(
      deviceId,
      _serviceId!,
      _writeCharacteristicId!,
      Uint8List.fromList(data),
      withoutResponse: true,
    );
  }

  @override
  Stream<List<int>> get notifyStream {
    if (_notifyCharacteristicId == null) {
      throw StateError('setDeviceUuids must be called before notifyStream');
    }
    return UniversalBle.characteristicValueStream(deviceId, _notifyCharacteristicId!);
  }

  @override
  Future<void> disconnect() async {
    await UniversalBle.disconnect(deviceId);
  }

  @override
  String get friendlyName => _cachedName ?? device.name ?? deviceId;
}

class BleUniversalRepository implements BleRepository {
  final _log = Logger("BleUniversalRepository");

  final Map<String, UniversalBleDevice> _discoveredBleDevices = {};
  final Map<String, StreamSubscription<bool>> _connectionSubscriptions = {};
  // Cache device names across scans. Android BLE sometimes returns a null name
  // even when the device matched by namePrefix (name is in the OS cache but not
  // in the current advertisement packet). We populate this whenever we see a
  // non-null name so that re-scans can still identify the device correctly.
  final Map<String, String> _deviceNameCache = {};

  StreamSubscription<BleDevice>? _scanSubscription;
  Timer? _scanTimer;
  final List<BleDevice> _pendingConnect = [];

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

  late StreamSubscription<AvailabilityState> _adapterStateSubscription;

  List<String>? _pendingScanServices;
  List<String>? _pendingScanNamePrefix;

  @override
  Future<void> init() async {
    // Set operation timeout before any connections.
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      UniversalBle.timeout = const Duration(seconds: 25);
    } else if (!kIsWeb) {
      UniversalBle.timeout = const Duration(seconds: 10);
    }

    if (kIsWeb) {
      // On web, BLE is user-gesture gated. Don't block; listen for state changes.
      _adapterStateSubscription = UniversalBle.availabilityStream.listen((state) {
        _updateAvailability(state);
        _bleEnabledSubscription.add(enabled && supported && permissioned);
      });
      supported = true;
      enabled = true;
      permissioned = true;
      _bleEnabledSubscription.add(true);
    } else {
      // Non-blocking: return immediately so the app can render.
      // Permissions check and queued scan are triggered when the adapter fires.
      _adapterStateSubscription = UniversalBle.availabilityStream.listen((state) async {
        final wasReady = enabled && supported;
        _updateAvailability(state);
        if (state == AvailabilityState.poweredOn && !wasReady) {
          if (!await UniversalBle.hasPermissions()) {
            await UniversalBle.requestPermissions();
          }
          permissioned = await UniversalBle.hasPermissions();
          _log.info('ble_repo BLE ready (supported=$supported, enabled=$enabled, permissioned=$permissioned)');
          _bleEnabledSubscription.add(enabled && supported && permissioned);
          _triggerPendingScan();
        } else {
          _bleEnabledSubscription.add(enabled && supported && permissioned);
        }
      });
      _bleEnabledSubscription.add(false);
      _log.info('ble_repo init returned (BLE adapter initializing asynchronously)');
    }
  }

  void _triggerPendingScan() {
    final services = _pendingScanServices;
    final namePrefix = _pendingScanNamePrefix;
    _pendingScanServices = null;
    _pendingScanNamePrefix = null;
    if (services != null || namePrefix != null) {
      unawaited(scan(services: services, namePrefix: namePrefix));
    }
  }

  @override
  Future<bool> isSupported() async {
    return supported;
  }

  void _updateAvailability(AvailabilityState state) {
    if (state == AvailabilityState.poweredOn) {
      supported = true;
      enabled = true;
    } else if (state == AvailabilityState.poweredOff) {
      enabled = false;
    } else if (state == AvailabilityState.unsupported ||
        state == AvailabilityState.unknown ||
        state == AvailabilityState.unauthorized) {
      supported = false;
      enabled = false;
    }
  }

  final Map<String, DateTime> _deviceLastSeen = {};

  @override
  Future<void> scan({List<String>? services, List<String>? namePrefix, Duration? timeout = const Duration(seconds: 5)}) async {
    if (!kIsWeb && (!supported || !enabled)) {
      _log.fine("scan() queued: BLE adapter not ready");
      _pendingScanServices = services;
      _pendingScanNamePrefix = namePrefix;
      return;
    }
    if (await UniversalBle.isScanning()) {
      _log.fine("scan() called while already scanning; ignoring");
      return;
    }

    _scanSubscription?.cancel();
    _scanTimer?.cancel();

    _scanSubscription = UniversalBle.scanStream.listen((BleDevice bleDevice) {
      final now = DateTime.now();
      final last = _deviceLastSeen[bleDevice.deviceId];
      if (last != null && now.difference(last) < const Duration(seconds: 2)) return;
      _deviceLastSeen[bleDevice.deviceId] = now;

      // Cache the name whenever the advertisement includes it.
      if (bleDevice.name != null && bleDevice.name!.isNotEmpty) {
        _deviceNameCache[bleDevice.deviceId] = bleDevice.name!;
      }

      final alreadyPending = _pendingConnect.any((d) => d.deviceId == bleDevice.deviceId);
      if (!_discoveredBleDevices.containsKey(bleDevice.deviceId) && !alreadyPending) {
        _log.info("discovered: ${_deviceNameCache[bleDevice.deviceId] ?? bleDevice.deviceId}");
        _pendingConnect.add(bleDevice);
        // On non-Windows native, connect immediately while scan continues.
        // iOS/macOS CoreBluetooth and Android BLE support connecting during scan.
        // Windows WinRT is less tolerant — it uses the batch path in _stopScanAndConnect.
        if (!kIsWeb && !Platform.isWindows) {
          unawaited(_connectDevice(bleDevice));
        }
      }
    });

    _log.info("ble scan start (services: ${services?.join(',') ?? 'any'})");
    try {
      await UniversalBle.startScan(scanFilter: ScanFilter(withServices: services ?? [], withNamePrefix: namePrefix ?? []));
    } catch (e, st) {
      // ignore: avoid_print
      print("[BLE] startScan error: $e");
      _log.severe("startScan error: $e", e, st);
      _scanSubscription?.cancel();
      _scanSubscription = null;
      if (!kIsWeb) rethrow;
      return;
    }

    // On web, startScan() awaits requestDevice() — by the time it returns the
    // device is already in _pendingConnect. Connect immediately, no timer needed.
    if (kIsWeb) {
      await _stopScanAndConnect();
      return;
    }

    _scanTimer = Timer(timeout ?? const Duration(seconds: 5), () async {
      await _stopScanAndConnect();
    });
  }

  Future<void> _connectDevice(BleDevice bleDevice) async {
    _pendingConnect.removeWhere((d) => d.deviceId == bleDevice.deviceId);
    try {
      await UniversalBle.connect(bleDevice.deviceId);
      _discoveredBleDevices[bleDevice.deviceId] = UniversalBleDevice(device: bleDevice, cachedName: _deviceNameCache[bleDevice.deviceId]);
      _bleDeviceSubscription.add(Map.of(_discoveredBleDevices));
      _setupConnectionListener(bleDevice.deviceId);
      _log.info("connected: ${_deviceNameCache[bleDevice.deviceId] ?? bleDevice.name ?? bleDevice.deviceId}");
    } catch (e, st) {
      _log.severe("connect error for ${bleDevice.deviceId}: $e", e, st);
    }
  }

  Future<void> _stopScanAndConnect() async {
    await UniversalBle.stopScan();
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    final pending = List.of(_pendingConnect);
    _pendingConnect.clear();
    _log.info("scan finished; connecting ${pending.length} device(s)");

    for (final bleDevice in pending) {
      if (!kIsWeb && Platform.isWindows) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      try {
        await UniversalBle.connect(bleDevice.deviceId);
        // Emit only after connection is established — DieDomain will then call
        // device.init() → discoverServices() on an already-connected device.
        _discoveredBleDevices[bleDevice.deviceId] = UniversalBleDevice(device: bleDevice, cachedName: _deviceNameCache[bleDevice.deviceId]);
        _bleDeviceSubscription.add(Map.of(_discoveredBleDevices));
        _setupConnectionListener(bleDevice.deviceId);
        _log.info("connected: ${_deviceNameCache[bleDevice.deviceId] ?? bleDevice.name ?? bleDevice.deviceId}");
      } catch (e, st) {
        _log.severe("connect error for ${bleDevice.deviceId}: $e", e, st);
      }
    }
  }

  void _setupConnectionListener(String deviceId) {
    _connectionSubscriptions[deviceId]?.cancel();
    _connectionSubscriptions[deviceId] =
        UniversalBle.connectionStream(deviceId).listen((bool isConnected) {
      if (!isConnected) {
        _log.warning("device disconnected: $deviceId");
        _discoveredBleDevices.remove(deviceId);
        _connectionSubscriptions[deviceId]?.cancel();
        _connectionSubscriptions.remove(deviceId);
        _bleDeviceSubscription.add(Map.of(_discoveredBleDevices));
      }
    });
  }

  @override
  Future<void> stopScan() async {
    if (await UniversalBle.isScanning()) await UniversalBle.stopScan();
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _pendingConnect.clear();
    _deviceLastSeen.clear();
  }

  @override
  Future<void> disconnectDevice(String deviceId) async {
    _connectionSubscriptions[deviceId]?.cancel();
    _connectionSubscriptions.remove(deviceId);
    _discoveredBleDevices.remove(deviceId);
    _bleDeviceSubscription.add(Map.of(_discoveredBleDevices));
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (e, st) {
      _log.warning('disconnect error for $deviceId: $e', e, st);
    }
  }

  @override
  Future<void> disconnectAllDevices() async {
    final ids = List.of(_discoveredBleDevices.keys);
    for (final deviceId in ids) {
      _connectionSubscriptions[deviceId]?.cancel();
      _connectionSubscriptions.remove(deviceId);
    }
    _discoveredBleDevices.clear();
    _bleDeviceSubscription.add(Map.of(_discoveredBleDevices));
    for (final deviceId in ids) {
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (e, st) {
        _log.warning('disconnect error for $deviceId: $e', e, st);
      }
    }
  }

  @override
  void dispose() {
    stopScan();
    _adapterStateSubscription.cancel();
    for (final sub in _connectionSubscriptions.values) {
      sub.cancel();
    }
    _connectionSubscriptions.clear();
    _bleDeviceSubscription.close();
    _bleEnabledSubscription.close();
  }
}
