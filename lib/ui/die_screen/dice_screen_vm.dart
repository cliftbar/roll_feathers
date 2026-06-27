import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/util/command.dart';

class DiceScreenViewModel extends ChangeNotifier {
  // init
  final DiWrapper _diWrapper;
  late Command0 load;

  /// The profile domain the Pixels profiles screen talks to (UI → domain only).
  PixelProfileDomain get pixelProfileDomain => _diWrapper.pixelProfileDomain;

  // rolling
  late Command0 clearRollResultHistory;
  late Command1<void, RollType> setRollType;
  late Command1<void, bool> setWithVirtualDice;
  late StreamSubscription<List<RollResult>> _rollResultsSubscription;
  late StreamSubscription<RollStatus> _rollStatusSubscription;
  late Command1<void, bool> rollAllVirtualDice;

  // die control settings
  late Command3<void, Color, GenericDie, String?> blink;
  late Command3<void, Color, RollingFlashPreset, GenericDie> previewRollingFlash;
  late Command2<void, GenericDie, DieSettings> updateDieSettings;
  late Command2<void, int, String> addVirtualDie;
  late Command0<void> disconnectAllDice;
  late Command1<void, String> disconnectDie;
  late Command0<void> removeAllVirtualDice;

  DiceScreenViewModel(this._diWrapper) {
    // init
    load = Command0(_load)..execute();

    // rolling
    clearRollResultHistory = Command0(_clearRollResultHistory);
    setRollType = Command1(_setRollType);
    setWithVirtualDice = Command1(_setWithVirtualDice);
    rollAllVirtualDice = Command1(_rollAllVirtualDice);
    _rollResultsSubscription = _diWrapper.rollDomain.subscribeRollResults().listen((rollResult) {
      notifyListeners();
    });

    _rollStatusSubscription = _diWrapper.rollDomain.subscribeRollStatus().listen((rollResult) {
      notifyListeners();
    });

    // die control settings
    blink = Command3(_blink);
    previewRollingFlash = Command3(_previewRollingFlash);
    updateDieSettings = Command2(_updateDieSettings);
    addVirtualDie = Command2(_addVirtualDie);

    disconnectAllDice = Command0(_disconnectAllDice);
    disconnectDie = Command1(_disconnectDie);
    removeAllVirtualDice = Command0(_removeAllVirtualDice);
  }

  // init
  Future<Result<void>> _load() async {
    try {
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  Map<String, GenericDie> get dice => _diWrapper.dieDomain.dice;
  List<RollResult> get rollHistory => _diWrapper.rollDomain.rollHistory;

  // rolling
  Stream<List<RollResult>> getResultsStream() {
    return _diWrapper.rollDomain.subscribeRollResults();
  }

  Future<Result<void>> _clearRollResultHistory() async {
    _diWrapper.rollDomain.clearRollResults();
    return Result.value(null);
  }

  Future<Result<void>> _setRollType(RollType rollType) async {
    _diWrapper.rollDomain.rollType = rollType;
    return Result.value(null);
  }

  Future<Result<void>> _setWithVirtualDice(bool withVirtualDice) async {
    _diWrapper.rollDomain.autoRollVirtualDice = withVirtualDice;
    return Result.value(null);
  }

  RollType getRollType() {
    return _diWrapper.rollDomain.rollType;
  }

  // die control settings
  Future<Result<void>> _blink(Color blinkColor, GenericDie die, String? entityOverride) async {
    _diWrapper.dieDomain.blink(blinkColor, die);
    return Result.value(null);
  }

  Future<Result<void>> _previewRollingFlash(Color color, RollingFlashPreset preset, GenericDie die) async {
    await _diWrapper.dieDomain.previewRollingFlash(die, color, preset);
    return Result.value(null);
  }

  // TODO: Refactor needed?  I'm not sure how the UI is getting notified about this?
  Stream<Map<String, GenericDie>> getDeviceStream() {
    return _diWrapper.dieDomain.getDiceStream();
  }

  Future<Result<void>> _updateDieSettings(GenericDie die, DieSettings settings) async {
    die.blinkColor = settings.blinkColor;
    die.haEntityTargets = settings.haEntityTargets;
    die.rollingFlashEnabled = settings.rollingFlashEnabled;
    die.rollingFlashColor = settings.rollingFlashColor;
    die.rollingFlashPreset = settings.rollingFlashPreset;
    if (settings.friendlyName != null) {
      die.friendlyName = settings.friendlyName!;
      // Pixels: push the name to the die's firmware so it persists on the die
      // itself and is visible to other apps (true BLE rename).
      if (die.type == GenericDieType.pixel && settings.friendlyName!.isNotEmpty) {
        await _diWrapper.dieDomain.setDieName(die, settings.friendlyName!);
      }
    }
    if (die.type != GenericDieType.pixel && settings.faceTypeName != null) {
      final dt = GenericDTypeFactory.getKnown(settings.faceTypeName!);
      if (dt != null) die.dType = dt;
    }
    await _diWrapper.appService.saveDieSettings(die.dieId, settings);
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _addVirtualDie(int faceCount, String name) async {
    _diWrapper.dieDomain.addVirtualDie(faceCount: faceCount, name: name);
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _rollAllVirtualDice(bool force) async {
    _diWrapper.rollDomain.rollAllVirtualDice(force: force);
    return Result.value(null);
  }

  Future<Result<void>> _disconnectAllDice() async {
    await _diWrapper.dieDomain.disconnectAllDice();
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _removeAllVirtualDice() async {
    _diWrapper.dieDomain.removeAllVirtualDice();
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _disconnectDie(String dieId) async {
    await _diWrapper.dieDomain.disconnectDie(dieId);
    notifyListeners();
    return Result.value(null);
  }

  GenericDie? getDieById(String dieId) {
    return _diWrapper.dieDomain.getDieById(dieId);
  }

  // Cleanup
  @override
  void dispose() {
    _rollResultsSubscription.cancel();
    _rollStatusSubscription.cancel();
    super.dispose();
  }
}
