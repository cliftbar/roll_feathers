import 'dart:async';
import 'dart:io';

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
    // Ensure the device is connected before attempting to discover services.
    try {
      await UniversalBle.connect(deviceId);
    } catch (e) {
      // If already connected, some platforms may throw; proceed to discovery.
      // ignore: avoid_print
      print("[WEB_BLE] connect (init) error or already connected for $deviceId: $e");
    }
    // Optionally wait for the connection to report as established.
    try {
      // Wait briefly for a 'connected' event; do not hang indefinitely.
      final sub = UniversalBle.connectionStream(deviceId).listen((_) {});
      await UniversalBle.connectionStream(deviceId)
          .firstWhere((isConnected) => isConnected == true)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      await sub.cancel();
    } catch (_) {
      // Swallow; discovery will still fail with a clear error if not connected.
    }

    _services = await UniversalBle.discoverServices(deviceId);
    log.fine("service length: ${_services.length}");
    _characteristics = _services.expand((s) => s.characteristics).toList();
    initialized = true;
    return initialized;
  }

  @override
  Future<void> discoverServices() async {
    // Ensure connected before service discovery to avoid Bad state errors on Web.
    try {
      await UniversalBle.connect(deviceId);
    } catch (_) {
      // Ignore if already connected or connection attempt races.
    }
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
  StreamSubscription<BleDevice>? _scanSubscription;
  Timer? _scanTimer;
  bool _isScanning = false;

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
    // On Web, do not block waiting for poweredOn; the permission prompt
    // happens only within a user gesture (when starting scan). We still
    // subscribe to availability updates but allow UI to proceed.
    if (kIsWeb) {
      _adapterStateStateSubscription = UniversalBle.availabilityStream.listen((state) {
        if (state == AvailabilityState.unsupported ||
            state == AvailabilityState.unknown ||
            state == AvailabilityState.unauthorized) {
          supported = false;
          enabled = false;
        } else if (state == AvailabilityState.poweredOn) {
          supported = true;
          enabled = true;
        }
        _bleEnabledSubscription.add(enabled && supported && permissioned);
      });
      // Optimistically allow Web to attempt scans; browser will gate by user gesture
      supported = true;
      enabled = true;
    } else {
      await _connect();
    }
    // Increase BLE operation timeout on desktop platforms to improve stability
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      UniversalBle.timeout = const Duration(seconds: 25);
    } else {
      UniversalBle.timeout = const Duration(seconds: 10);
    }
    supported = await isSupported();
    if (!supported) {
      _log.severe("Bluetooth is not supported");
    }
    if (kIsWeb) {
      permissioned = true;
    } else if (Platform.isAndroid || Platform.isIOS) {
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
  final Map<String, DateTime> _deviceLastSeen = {};

  @override
  Future<void> scan({List<String>? services, Duration? timeout = const Duration(seconds: 5)}) async {
    // On Web, allow scan even if we haven't yet observed poweredOn; the
    // browser permission flow will manage availability. On other platforms,
    // keep the safety gate.
    if (!kIsWeb && (!supported || !enabled)) {
      return;
    }
    if (_isScanning) {
      _log.fine("scan() called while already scanning; ignoring");
      return;
    }
    _isScanning = true;
    _log.info("ble scan start (services: ${services?.join(',') ?? ''})");
    _scanSubscription?.cancel();
    _scanTimer?.cancel();

    _scanSubscription = UniversalBle.scanStream.listen((BleDevice bleDevice) async {
      // Simple per-device debounce to avoid rapid rediscoveries
      final now = DateTime.now();
      final last = _deviceLastSeen[bleDevice.deviceId];
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        return;
      }
      _deviceLastSeen[bleDevice.deviceId] = now;

      // Emit device immediately on discovery (before connect) and keep it listed
      _discoveredBleDevices[bleDevice.deviceId] = UniversalBleDevice(device: bleDevice);
      _bleDeviceSubscription.add(_discoveredBleDevices);

      // Web: do not auto-connect during scan; let user initiate connect
      if (kIsWeb) {
        return;
      }

      // Small per-device throttle before connecting to reduce scan/connect collisions on Windows
      if (Platform.isWindows) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      try {
        await UniversalBle.connect(bleDevice.deviceId);
        UniversalBle.connectionStream(bleDevice.deviceId).listen((bool isConnected) async {
          if (!isConnected) {
            if (_discoveredBleDevices.containsKey(bleDevice.deviceId)) {
              // Keep the device listed; optional reconnect policy can be implemented later
              int reconnects = _deviceReconnects.putIfAbsent(bleDevice.deviceId, () => 0);
              if (reconnects < 0) {
                await Future.delayed(Duration(seconds: 1 * reconnects));
                await UniversalBle.connect(bleDevice.deviceId);
                _log.warning("attempting reconnect on ${bleDevice.deviceId} ${await bleDevice.connectionState}");
              } else {
                _log.warning("device disconnected ${bleDevice.deviceId} ${await bleDevice.connectionState}");
              }
            }
            _bleDeviceSubscription.add(_discoveredBleDevices);
          }
        });
      } catch (e, st) {
        _log.severe("connect error for ${bleDevice.deviceId}: $e", e, st);
      }
    });

    // Start scanning
    try {
      await UniversalBle.startScan(scanFilter: ScanFilter(withServices: services ?? []));
    } catch (e, st) {
      // On web this is often a DOMException with useful text
      // Use print so it appears in the browser console as well
      // ignore: avoid_print
      print("[WEB_BLE] startScan error: $e");
      _log.severe("startScan error: $e", e, st);
      // Ensure we clean up scanning state on failure
      _isScanning = false;
      _scanSubscription?.cancel();
      _scanSubscription = null;
      // In Web builds, bubbling this exception can surface as a generic
      // "Uncaught Error" in minified JS. We already logged the error, so
      // suppress rethrow on Web to avoid breaking the UI. Keep native behavior
      // (rethrow) on other platforms so callers can handle it explicitly.
      if (!kIsWeb) {
        rethrow;
      }
    }

    _scanTimer = Timer(timeout ?? const Duration(seconds: 5), () {
      UniversalBle.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _log.info("Scan finished");
    });
  }

  // Stop scanning for devices
  @override
  Future<void> stopScan() async {
    await UniversalBle.stopScan();
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
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
