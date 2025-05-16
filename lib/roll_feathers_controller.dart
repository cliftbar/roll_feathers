import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:roll_feathers/pixel/pixel.dart';

class BluetoothNotSupported extends FlutterBluePlusException {
  BluetoothNotSupported(
    super.platform,
    super.function,
    super.code,
    super.description,
  );
}

class RollFeathersController {
  final BleScanManager _scanManager = BleScanManager();
  bool _initialized = false;
  final Map<String, int> _rollingDie = {};
  Timer? _rollUpdateTimer;
  bool _isRolling = false;

  void init() {
    _initializeBle();
  }

  void dispose() {
    _scanManager.dispose();
    _rollUpdateTimer?.cancel();
  }

  Future<void> _initializeBle() async {
    if (_initialized) return;

    var supported = await _scanManager.checkSupported();
    if (!supported) {
      throw BluetoothNotSupported(
        ErrorPlatform.fbp,
        "_initializeBle()",
        -1,
        "Bluetooth is not supported",
      );
    }

    await _scanManager.connect();

    _initialized = true;
    await startScanning();
  }

  Future<void> startScanning() async {
    print("_startScanning()");
    await _scanManager.scanForDevices();
  }

  Stream<List<PixelDie>> getDeviceStream() {
    return _scanManager.deviceStream;
  }

  bool isRolling() {
    return _isRolling;
  }

  void startRolling(Function(Timer) timerCallback) {
    _isRolling = true;
    _rollingDie.clear();
    _rollUpdateTimer?.cancel();
    _rollUpdateTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      timerCallback,
    );
  }

  void stopRolling() {
    _rollUpdateTimer?.cancel();
    _isRolling = false;
  }

  void updateDieValue(PixelDie die) {
    _rollingDie[die.device.remoteId.str] = die.state.currentFaceValue!;
  }

  int rollMax() {
    return _rollingDie.values.fold(-1, max);
  }

  int rollMin() {
    if (_rollingDie.isEmpty) {
      return -1;
    }
    return _rollingDie.values.reduce(min);
  }

  int rollTotal() {
    return _rollingDie.values.fold(0, (p, c) => p + c);
  }
}
