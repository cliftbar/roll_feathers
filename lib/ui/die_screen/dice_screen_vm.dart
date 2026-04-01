import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/util/command.dart';

class DiceScreenViewModel extends ChangeNotifier {
  // init
  final DiWrapper _diWrapper;
  late Command0 load;

  // rolling
  late Command0 clearRollResultHistory;
  late Command1<void, RollType> setRollType;
  late Command1<void, bool> setWithVirtualDice;
  late StreamSubscription<List<RollResult>> _rollResultsSubscription;
  late StreamSubscription<RollStatus> _rollStatusSubscription;
  late Command1<void, bool> rollAllVirtualDice;

  // die control settings
  late Command3<void, Color, GenericDie, String?> blink;
  late Command4<void, GenericDie, Color, String, GenericDType> updateDieSettings;
  late Command2<void, int, String> addVirtualDie;
  late Command0<void> disconnectAllDice;
  late Command1<void, String> disconnectDie;

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
    updateDieSettings = Command4(_updateDieSettings);
    addVirtualDie = Command2(_addVirtualDie);

    disconnectAllDice = Command0(_disconnectAllDice);
    disconnectDie = Command1(_disconnectDie);
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
    _diWrapper.dieDomain.blink(die.blinkColor ?? Colors.white, die);

    return Result.value(null);
  }

  // TODO: Refactor needed?  I'm not sure how the UI is getting notified about this?
  Stream<Map<String, GenericDie>> getDeviceStream() {
    return _diWrapper.dieDomain.getDiceStream();
  }

  Future<Result<void>> _updateDieSettings(
    GenericDie die,
    Color blinkColor,
    String entity,
    GenericDType faceCount,
  ) async {
    die.blinkColor = blinkColor;
    die.haEntityTargets = [entity];
    if (die.type != GenericDieType.pixel) {
      die.dType = faceCount;
    }
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
