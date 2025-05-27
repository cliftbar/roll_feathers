import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:roll_feathers/repositories/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';

class PixelDieDomain {
  final BleRepository _bleRepository;
  final HaRepository _haRepository;

  final _pixelDiceSubscription = StreamController<Map<String, PixelDie>>.broadcast();

  PixelDieDomain(this._bleRepository, this._haRepository) {
    _bleRepository.subscribeBleDevices().asyncMap(asyncConvert).listen((data) {
      _pixelDiceSubscription.add(data);
    });
  }

  Future<Map<String, PixelDie>> asyncConvert(Map<String, fbp.BluetoothDevice> data) async {
    Map<String, PixelDie> converted = {};

    for (var device in List.of(data.values)) {
      var pd = await PixelDie.fromDevice(device);
      converted[pd.deviceId] = pd;
    }
    return converted;
  }

  void dispose() {
    _bleRepository.dispose();
  }

  Stream<Map<String, PixelDie>> getDeviceStream() {
    return _pixelDiceSubscription.stream;
  }

  void blink(Color blinkColor, PixelDie die) async {
    var blinker = BlinkMessage(blinkColor: blinkColor);

    _haRepository.blinkEntity(blink: blinker, entity: die.haEntityTargets.firstOrNull);
    die.sendMessage(blinker);
  }
}
