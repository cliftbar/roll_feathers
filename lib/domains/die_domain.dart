import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';
import 'package:roll_feathers/repositories/ble_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';

class PixelDieDomain {
  final BleRepository _bleRepository;
  final HaRepository _haRepository;
  final Map<String, GenericBleDie> _foundDie = {};

  final _pixelDiceSubscription = StreamController<Map<String, GenericBleDie>>.broadcast();

  PixelDieDomain(this._bleRepository, this._haRepository) {
    _bleRepository.subscribeBleDevices().asyncMap(asyncConvertToDie).listen((data) {
      _pixelDiceSubscription.add(data);
    });
  }

  Future<Map<String, GenericBleDie>> asyncConvertToDie(Map<String, fbp.BluetoothDevice> data) async {
    for (var device in List.of(data.values)) {
      if (!_foundDie.containsKey(device.remoteId.str)) {
        var pd = await GenericBleDie.fromDevice(device);
        _foundDie[pd.deviceId] = pd;
      }
    }
    for (String id in List.of(_foundDie.keys)) {
      if (!data.containsKey(id)) {
        _foundDie.remove(id);
      }
    }
    return _foundDie;
  }

  void dispose() {
    _bleRepository.dispose();
  }

  Stream<Map<String, GenericBleDie>> getDeviceStream() {
    return _pixelDiceSubscription.stream;
  }

  void blink(Color blinkColor, GenericBleDie die) async {
    Blinker blinker;
    switch (die.type) {
      case GenericDieType.godice:
        blinker = MessageToggleLeds(toggleColor: blinkColor);
      case GenericDieType.pixel:
        blinker = MessageBlink(blinkColor: blinkColor);
    }

    _haRepository.blinkEntity(blink: blinker, entity: die.haEntityTargets.firstOrNull);
    die.sendMessage(blinker);
  }
}
