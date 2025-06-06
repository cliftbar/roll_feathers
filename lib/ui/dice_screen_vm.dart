import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/util/command.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class DiceScreenViewModel extends ChangeNotifier {
  // init
  final DiWrapper _diWrapper;
  late Command0 load;

  // theme
  ThemeMode themeMode = ThemeMode.system;
  late Command0 toggleTheme;

  // screen wake lock
  bool keepScreenOn = false;
  late Command0 toggleKeepScreenOn;
  late StreamSubscription<bool> _keepScreenOnSubscription;

  // ble
  late Command0 startBleScan;
  bool _bleEnabled = false;
  late StreamSubscription<bool> _bleEnabledSubscription;

  // ha config proxy
  late HaConfig _haConfig;
  late Command4<void, bool, String, String, String> setHaConfig;
  late StreamSubscription<HaConfig> _haConfigSubscription;

  // rolling
  late Command0 clearRollResultHistory;
  late Command1<void, RollType> setRollType;
  late Command1<void, bool> setWithVirtualDice;
  late StreamSubscription<List<RollResult>> _rollResultsSubscription;
  late StreamSubscription<RollStatus> _rollStatusSubscription;
  late Command0<void> rollAllVirtualDice;

  // die control settings
  late Command3<void, Color, GenericDie, String?> blink;
  late Command3<void, GenericDie, Color, String> updateDieSettings;
  late Command2<void, int, String> addVirtualDie;
  late Command0<void> disconnectAllDice;
  late Command0<void> disconnectAllNonVirtualDice;
  late Command1<void, String> disconnectDie;

  DiceScreenViewModel(this._diWrapper) {
    // init
    load = Command0(_load)..execute();

    // theme
    toggleTheme = Command0(_toggleTheme);

    // screen wake lock
    toggleKeepScreenOn = Command0(_toggleKeepScreenOn);
    _keepScreenOnSubscription = _diWrapper.appRepository.observeKeepScreenOn().listen((enabled) {
      keepScreenOn = enabled;
      WakelockPlus.toggle(enable: enabled);
      notifyListeners();
    });

    // ble
    startBleScan = Command0(_startBleScan);
    _bleEnabledSubscription = _diWrapper.bleRepository.subscribeBleEnabled().listen((enabled) {
      _bleEnabled = enabled;
      notifyListeners();
    });

    // ha config proxy
    setHaConfig = Command4(_setHaConfig);
    _haConfigSubscription = _diWrapper.haRepository.subscribeHaSettings().listen((conf) {
      _haConfig = conf;
      notifyListeners();
    });

    // rolling
    clearRollResultHistory = Command0(_clearRollResultHistory);
    setRollType = Command1(_setRollType);
    setWithVirtualDice = Command1(_setWithVirtualDice);
    rollAllVirtualDice = Command0(_rollAllVirtualDice);
    _rollResultsSubscription = _diWrapper.rollDomain.subscribeRollResults().listen((rollResult) {
      notifyListeners();
    });

    _rollStatusSubscription = _diWrapper.rollDomain.subscribeRollStatus().listen((rollResult) {
      notifyListeners();
    });

    // die control settings
    blink = Command3(_blink);
    updateDieSettings = Command3(_updateDieSettings);
    addVirtualDie = Command2(_addVirtualDie);

    disconnectAllDice = Command0(_disconnectAllDice);
    disconnectAllNonVirtualDice = Command0(_disconnectAllNonVirtualDice);
    disconnectDie = Command1(_disconnectDie);
  }

  // init
  Future<Result<void>> _load() async {
    try {
      final themeResult = await _diWrapper.appRepository.getThemeMode();
      if (themeResult.isValue && themeResult.asValue != null) {
        themeMode = themeResult.asValue!.value;
      }

      final keepScreenOnResult = await _diWrapper.appRepository.getKeepScreenOn();
      if (keepScreenOnResult.isValue && keepScreenOnResult.asValue != null) {
        keepScreenOn = keepScreenOnResult.asValue!.value;
        WakelockPlus.toggle(enable: keepScreenOn);
      }

      _haConfig = await _diWrapper.haRepository.getHaConfig();
      return themeResult;
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  // theme
  ThemeMode getThemeMode() => themeMode;
  Future<Result<void>> _toggleTheme() async {
    try {
      themeMode = themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      return await _diWrapper.appRepository.setThemeMode(themeMode);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  // screen wake lock
  bool getKeepScreenOn() => keepScreenOn;
  Future<Result<void>> _toggleKeepScreenOn() async {
    try {
      keepScreenOn = !keepScreenOn;
      return await _diWrapper.appRepository.setKeepScreenOn(keepScreenOn);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  // ble
  Future<Result<void>> _startBleScan() async {
    await _diWrapper.bleRepository.scan(services: [pixelsService]);
    return Result.value(null);
  }

  // ha config proxy
  HaConfig getHaConfig() => _haConfig;
  Future<Result<void>> _setHaConfig(bool enabled, String url, String token, String entity) async {
    _diWrapper.haRepository.updateSettings(enabled: enabled, url: url, token: token, entity: entity);

    return Result.value(null);
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
  Map<String, Color> get blinkColors => _diWrapper.rollDomain.blinkColors;
  Future<Result<void>> _blink(Color blinkColor, GenericDie die, String? entityOverride) async {
    _diWrapper.rfController.blink(blinkColor, die);

    return Result.value(null);
  }

  // TODO: Refactor needed?  I'm not sure how the UI is getting notified about this?
  Stream<Map<String, GenericDie>> getDeviceStream() {
    return _diWrapper.rfController.getDiceStream();
  }

  Future<Result<void>> _updateDieSettings(GenericDie die, Color blinkColor, String entity) async {
    _diWrapper.rollDomain.blinkColors[die.dieId] = blinkColor;
    die.haEntityTargets = [entity];
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _addVirtualDie(int faceCount, String name) async {
    _diWrapper.rfController.addVirtualDie(faceCount: faceCount, name: name);
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _rollAllVirtualDice() async {
    _diWrapper.rollDomain.rollAllVirtualDice();
    return Result.value(null);
  }

  Future<Result<void>> _disconnectAllDice() async {
    await _diWrapper.rfController.disconnectAllDice();
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _disconnectAllNonVirtualDice() async {
    await _diWrapper.rfController.disconnectAllNonVirtualDice();
    notifyListeners();
    return Result.value(null);
  }

  Future<Result<void>> _disconnectDie(String dieId) async {
    await _diWrapper.rfController.disconnectDie(dieId);
    notifyListeners();
    return Result.value(null);
  }

  // Cleanup
  @override
  void dispose() {
    _haConfigSubscription.cancel();
    _rollResultsSubscription.cancel();
    _rollStatusSubscription.cancel();
    _bleEnabledSubscription.cancel();
    _keepScreenOnSubscription.cancel();
    _diWrapper.appRepository.setKeepScreenOn(false);
    super.dispose();
  }

  List<String> getIpAddress() {
    return _diWrapper.apiDomain.getIpAddress();
  }

  bool bleIsEnabled() {
    return _bleEnabled;
  }
}
