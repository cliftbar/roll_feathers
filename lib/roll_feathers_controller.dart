import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:roll_feathers/pixel/ha.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';

class BluetoothNotSupported extends FlutterBluePlusException {
  BluetoothNotSupported(super.platform, super.function, super.code, super.description);
}

enum RollType { sum, advantage, disadvantage }

class RollFeathersController {
  final BleScanManager _scanManager = BleScanManager();
  bool _initialized = false;
  final Map<String, int> _rollingDie = {};
  Timer? _rollUpdateTimer;
  bool _isRolling = false;
  final HomeAssistantController _homeAssistantController = HomeAssistantController();

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
      throw BluetoothNotSupported(ErrorPlatform.fbp, "_initializeBle()", -1, "Bluetooth is not supported");
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
    _rollUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), timerCallback);
  }

  void stopRolling() {
    _rollUpdateTimer?.cancel();
    _isRolling = false;
  }

  static const Color green = Color.fromARGB(255, 0, 255, 0);
  static const Color red = Color.fromARGB(255, 255, 0, 0);
  static const Color blue = Color.fromARGB(255, 0, 0, 255);

  int stopRollWithResult({
    RollType rollType = RollType.sum,
    Color? advBlink = green,
    Color? disAdvBlink = red,
    Map<String, Color>? totalColors,
  }) {
    switch (rollType) {
      case RollType.advantage:
        var maxRoll = _rollingDie.entries.reduce((v, e) => v.value >= e.value ? v : e);
        var maxDie = _scanManager.getDiscoveredDevices()[maxRoll.key];
        if (advBlink != null && maxDie != null) {
          blink(advBlink, maxDie);
        }
        return maxRoll.value;
      case RollType.disadvantage:
        var minRoll = _rollingDie.entries.reduce((v, e) => v.value <= e.value ? v : e);
        var minDie = _scanManager.getDiscoveredDevices()[minRoll.key];
        if (disAdvBlink != null && minDie != null) {
          blink(disAdvBlink, minDie);
        }
        return minRoll.value;
      default:
        for (var k in _rollingDie.keys) {
          var d = _scanManager.getDiscoveredDevices()[k];
          if (d != null) {
            blink(totalColors?[k] ?? blue, d);
          }
        }
        return rollTotal();
    }
  }

  void updateDieValue(PixelDie die) {
    _rollingDie[die.device.remoteId.str] = die.state.currentFaceValue!;
  }

  void addDieEntity(PixelDie die, String entity) {
    die.haEntityTargets = [entity];
    _scanManager.updateDeviceDieEntity(die, entity);
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

  void blink(Color blinkColor, PixelDie die) {
    var blinker = BlinkMessage(blinkColor: blinkColor);
    die.sendMessage(blinker);
    if (_homeAssistantController.getHaSettings().enabled) {
      var blinkEntity = _homeAssistantController.getHaSettings().entity;
      if (die.haEntityTargets.isNotEmpty && die.haEntityTargets.first.isNotEmpty) {
        blinkEntity = die.haEntityTargets.first;
      }
      _homeAssistantController.blinkEntity(blinkEntity, blinker);
    }
  }

  void updateHaSettings({bool enabled = false, String? url, String? token, String? entity}) {
    _homeAssistantController.updateSettings(enabled: enabled, url: url, token: token, entity: entity);
  }

  HaSettings getHaSettings() {
    return _homeAssistantController.getHaSettings();
  }
}

