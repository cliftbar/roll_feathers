import 'dart:async';

import 'package:flutter/material.dart';

import '../dice_sdks/dice_sdks.dart';
import '../dice_sdks/godice.dart';
import '../dice_sdks/message_sdk.dart';
import '../dice_sdks/pixels.dart';
import '../repositories/ble/ble_repository.dart';
import '../repositories/home_assistant_repository.dart';
import '../services/app_service.dart';

class DieDomain {
  final BleRepository _bleRepository;
  final HaRepository _haRepository;
  final AppService? _appService;
  final Map<String, GenericDie> _foundDie = {};

  final _diceSubscription = StreamController<Map<String, GenericDie>>.broadcast();
  late StreamSubscription<Map<String, GenericDie>> _bleDevicesSub;

  DieDomain(this._bleRepository, this._haRepository, [this._appService]) {
    _bleDevicesSub = _bleRepository.subscribeBleDevices().asyncMap(asyncConvertToDie).listen((data) {
      _diceSubscription.add(data);
    });
  }

  void addVirtualDie({required int faceCount, String? dieId, String? name}) {
    var dType =
        GenericDTypeFactory.fromIntId(faceCount) ??
        GenericDType("d${faceCount.toString()}", faceCount, faceCount, 0, 1);
    var vd = VirtualDie(dType: dType, name: name);
    _foundDie[vd.dieId] = vd;
    _diceSubscription.add(_foundDie);
  }

  int get dieCount => _foundDie.length;

  List<VirtualDie> getVirtualDice() {
    var res = _foundDie.values.toList().where((d) => d.type == GenericDieType.virtual).toList();
    var res2 = res.map((d) => d as VirtualDie).toList();
    return res2;
  }

  GenericDie? getDieById(String dieId) {
    return _foundDie[dieId];
  }

  Future<Map<String, GenericDie>> asyncConvertToDie(Map<String, BleDeviceWrapper> data) async {
    for (var device in List.of(data.values)) {
      if (!_foundDie.containsKey(device.deviceId)) {
        var pd = await GenericBleDie.fromDevice(device);
        pd.onStateChanged = () {
          if (_foundDie.containsKey(pd.dieId)) {
            _diceSubscription.add(Map.of(_foundDie));
          }
        };
        // Restore persisted settings if available.
        if (_appService != null) {
          final saved = await _appService.getDieSettings(pd.dieId);
          if (saved != null) {
            pd.friendlyName = saved.friendlyName ?? pd.friendlyName;
            pd.blinkColor = saved.blinkColor;
            pd.haEntityTargets = saved.haEntityTargets;
            pd.rollingFlashEnabled = saved.rollingFlashEnabled;
            pd.rollingFlashColor = saved.rollingFlashColor;
            pd.rollingFlashPreset = saved.rollingFlashPreset;
            pd.useGlobalSounds = saved.useGlobalSounds;
            if (saved.faceTypeName != null && pd.type != GenericDieType.pixel) {
              final dt = GenericDTypeFactory.getKnown(saved.faceTypeName!);
              if (dt != null) pd.dType = dt;
            }
          }
        }
        _foundDie[pd.dieId] = pd;
      }
    }
    for (GenericDie d in List.of(_foundDie.values.where((d) => d.type != GenericDieType.virtual))) {
      if (!data.containsKey(d.dieId)) {
        if (d is GenericBleDie) d.dispose();
        _foundDie.remove(d.dieId);
      }
    }
    return _foundDie;
  }

  void dispose() {
    _bleDevicesSub.cancel();
    _bleRepository.dispose();
  }

  Stream<Map<String, GenericDie>> getDiceStream() {
    return _diceSubscription.stream;
  }

  Map<String, GenericDie> get dice => Map.unmodifiable(_foundDie);

  // Disconnect a specific die
  Future<void> disconnectDie(String dieId) async {
    final die = _foundDie[dieId];
    if (die == null) return;
    if (die is GenericBleDie) die.dispose();
    _foundDie.remove(dieId);
    _diceSubscription.add(Map.of(_foundDie));
    if (die.type != GenericDieType.virtual) {
      await _bleRepository.disconnectDevice(dieId);
    }
  }

  // Disconnect all dice (including virtual)
  Future<void> disconnectAllDice() async {
    await _bleRepository.disconnectAllDevices();
    for (final die in _foundDie.values) {
      if (die is GenericBleDie) die.dispose();
    }
    _foundDie.clear();
    _diceSubscription.add(Map.of(_foundDie));
  }

  void removeAllVirtualDice() {
    _foundDie.removeWhere((_, die) => die.type == GenericDieType.virtual);
    _diceSubscription.add(Map.of(_foundDie));
  }

  // Disconnect all non-virtual dice
  Future<void> disconnectAllNonVirtualDice() async {
    await _bleRepository.disconnectAllDevices();
    final toRemove = _foundDie.entries.where((e) => e.value.type != GenericDieType.virtual).toList();
    for (final e in toRemove) {
      if (e.value is GenericBleDie) (e.value as GenericBleDie).dispose();
      _foundDie.remove(e.key);
    }
    _diceSubscription.add(Map.of(_foundDie));
  }

  Future<void> blink(
    Color blinkColor,
    GenericDie die, {
    bool withHa = true,
    int blinkCount = 2,
    Duration blinkInterval = const Duration(milliseconds: 500),
  }) async {
    Blinker? blinker;
    switch (die.type) {
      case GenericDieType.godice:
        MessageToggleLeds blinkMsg = MessageToggleLeds(
          toggleColor: blinkColor,
          numberOfBlinks: blinkCount,
          lightOffDuration10ms: blinkInterval.inMilliseconds ~/ 20,
          lightOnDuration10ms: blinkInterval.inMilliseconds ~/ 20,
        );
        blinker = blinkMsg;
        await (die as GoDiceBle).sendMessage(blinkMsg);
      case GenericDieType.pixel:
        MessageBlink blinkMsg = MessageBlink(
          blinkColor: blinkColor,
          duration: blinkInterval.inMilliseconds,
          loopCount: blinkCount,
        );
        blinker = blinkMsg;
        await (die as PixelDie).sendMessage(blinkMsg);
      case GenericDieType.virtual:
        blinker = BasicBlinker(1, Duration(milliseconds: 500), Duration(milliseconds: 500), blinkColor);
    }

    if (withHa) {
      await _haRepository.blinkEntity(blink: blinker, entity: die.haEntityTargets.firstOrNull);
    }
  }

  /// Stops all animations currently playing on [die].
  /// No-op for non-Pixels dice.
  Future<void> stopAnimations(GenericDie die) async {
    if (die is PixelDie) {
      await die.sendMessage(MessageStopAllAnimations());
    }
  }

  static ({int onMs, int offMs, int fade}) _presetTiming(RollingFlashPreset preset) =>
      switch (preset) {
        RollingFlashPreset.strobe  => (onMs: 50,  offMs: 50,  fade: 0),
        RollingFlashPreset.pulse   => (onMs: 400, offMs: 200, fade: 0),
        RollingFlashPreset.breathe => (onMs: 600, offMs: 600, fade: 128),
      };

  /// Sends a short finite preview of the rolling flash animation.
  /// Uses the supplied [color] and [preset] rather than the die's saved settings,
  /// so the user can preview unsaved changes from the settings dialog.
  /// No-op for non-Pixels dice.
  Future<void> previewRollingFlash(GenericDie die, Color color, RollingFlashPreset preset) async {
    if (die is! PixelDie) return;
    final t = _presetTiming(preset);
    await die.sendMessage(MessageBlink(
      blinkColor: color,
      duration: t.onMs,
      count: 1,
      fade: t.fade,
      loopCount: 3,
    ));
  }

  /// Sends an infinite looping blink to [die] while it is rolling.
  /// No-op if [die.rollingFlashEnabled] is false or [die] is not a Pixels die.
  Future<void> blinkRolling(GenericDie die) async {
    if (die is! PixelDie) return;
    if (!die.rollingFlashEnabled) return;
    final color = die.rollingFlashColor ?? Colors.white;
    final t = _presetTiming(die.rollingFlashPreset);
    await die.sendMessage(MessageBlink(
      blinkColor: color,
      duration: t.onMs,
      count: 1,
      fade: t.fade,
      loopCount: 255,
    ));
  }
}
