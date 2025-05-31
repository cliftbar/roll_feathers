import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:roll_feathers/dice_sdks/generic_die.dart';
import 'package:roll_feathers/repositories/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';

import 'package:roll_feathers/dice_sdks/pixels.dart';

class PixelDieDomain {
  final BleRepository _bleRepository;
  final HaRepository _haRepository;

  final _pixelDiceSubscription = StreamController<Map<String, GenericBleDie>>.broadcast();

  PixelDieDomain(this._bleRepository, this._haRepository) {
    _bleRepository.subscribeBleDevices().asyncMap(asyncConvertToDie).listen((data) {
      _pixelDiceSubscription.add(data);
    });
  }

  Future<Map<String, GenericBleDie>> asyncConvertToDie(Map<String, fbp.BluetoothDevice> data) async {
    Map<String, GenericBleDie> converted = {};

    for (var device in List.of(data.values)) {
      var pd = await GenericBleDie.fromDevice(device);
      converted[pd.deviceId] = pd;
    }
    return converted;
  }

  void dispose() {
    _bleRepository.dispose();
  }

  Stream<Map<String, GenericBleDie>> getDeviceStream() {
    return _pixelDiceSubscription.stream;
  }

  void blink(Color blinkColor, GenericBleDie die) async {
    var blinker = BlinkMessage(blinkColor: blinkColor);

    _haRepository.blinkEntity(blink: blinker, entity: die.haEntityTargets.firstOrNull);
    die.sendMessage(blinker);
  }
}
