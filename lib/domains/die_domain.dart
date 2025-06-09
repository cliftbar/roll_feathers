import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../dice_sdks/dice_sdks.dart';
import '../dice_sdks/godice.dart';
import '../dice_sdks/message_sdk.dart';
import '../dice_sdks/pixels.dart';
import '../repositories/ble/ble_repository.dart';
import '../repositories/home_assistant_repository.dart';

class DieDomain {
  final BleRepository _bleRepository;
  final HaRepository _haRepository;
  final Map<String, GenericDie> _foundDie = {};

  final _diceSubscription = StreamController<Map<String, GenericDie>>.broadcast();

  DieDomain(this._bleRepository, this._haRepository) {
    _bleRepository.subscribeBleDevices().asyncMap(asyncConvertToDie).listen((data) {
      _diceSubscription.add(data);
    });
  }

  void addVirtualDie({required faceCount, String? dieId, String? name}) {
    var vd = VirtualDie(faceCount: faceCount, name: name);
    _foundDie[vd.dieId] = vd;
    _diceSubscription.add(_foundDie);
  }

  List<VirtualDie> getVirtualDice() {
    var res = _foundDie.values.toList().where((d) => d.type == GenericDieType.virtual).toList();
    var res2 = res.map((d) => d as VirtualDie).toList();
    return res2;
  }

  Future<Map<String, GenericDie>> asyncConvertToDie(Map<String, BleDeviceWrapper> data) async {
    for (var device in List.of(data.values)) {
      if (!_foundDie.containsKey(device.deviceId)) {
        var pd = await GenericBleDie.fromDevice(device);
        _foundDie[pd.dieId] = pd;
      }
    }
    for (GenericDie d in List.of(_foundDie.values.where((d) => d.type != GenericDieType.virtual))) {
      if (!data.containsKey(d.dieId)) {
        _foundDie.remove(d.dieId);
      }
    }
    return _foundDie;
  }

  void dispose() {
    _bleRepository.dispose();
  }

  Stream<Map<String, GenericDie>> getDiceStream() {
    return _diceSubscription.stream;
  }

  // Disconnect a specific die
  Future<void> disconnectDie(String dieId) async {
    if (_foundDie.containsKey(dieId)) {
      GenericDie die = _foundDie[dieId]!;
      if (die.type != GenericDieType.virtual) {
        await _bleRepository.disconnectDevice(dieId);
        // The die will be removed from _foundDie in asyncConvertToDie when the BLE device is disconnected
      } else {
        _foundDie.remove(dieId);
        _diceSubscription.add(_foundDie);
      }
    }
  }

  // Disconnect all dice (including virtual)
  Future<void> disconnectAllDice() async {
    // Disconnect all BLE devices
    await _bleRepository.disconnectAllDevices();

    // Remove all virtual dice
    _foundDie.removeWhere((_, die) => die.type == GenericDieType.virtual);

    // Update subscribers
    _diceSubscription.add(_foundDie);
  }

  // Disconnect all non-virtual dice
  Future<void> disconnectAllNonVirtualDice() async {
    // Disconnect all BLE devices
    await _bleRepository.disconnectAllDevices();

    // Keep only virtual dice
    List<String> keys = _foundDie.keys.toList();
    for (var id in keys) {
      if (_foundDie[id]?.type != GenericDieType.virtual) {
        _foundDie.remove(id);
      }
    }
    // Update subscribers
    _diceSubscription.add(_foundDie);
  }

  void blink(Color blinkColor, GenericDie die) async {
    Blinker? blinker;
    switch (die.type) {
      case GenericDieType.godice:
        blinker = MessageToggleLeds(toggleColor: blinkColor);
        (die as GoDiceBle).sendMessage(blinker);
      case GenericDieType.pixel:
        blinker = MessageBlink(blinkColor: blinkColor);
        (die as PixelDie).sendMessage(blinker);
      default:
        {}
    }

    if (blinker != null) {
      _haRepository.blinkEntity(blink: blinker, entity: die.haEntityTargets.firstOrNull);
    }
  }
}
