import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/util/command.dart';

class MainScreenViewModel extends ChangeNotifier {
  // init
  final DiWrapper _diWrapper;
  late Command0 load;

  // theme
  ThemeMode themeMode = ThemeMode.system;
  late Command0 toggleTheme;

  // ble
  late Command0 startBleScan;

  // ha config proxy
  late HaConfig _haConfig;
  late Command4<void, bool, String, String, String> setHaConfig;
  late StreamSubscription<HaConfig> _haConfigSubscription;

  // rolling
  late Command0 clearRollResultHistory;
  late Command1<void, RollType> setRollType;
  late StreamSubscription<List<RollResult>> _rollResultsSubscription;
  late StreamSubscription<RollStatus> _rollStatusSubscription;

  // die control settings
  late Command3<void, Color, PixelDie, String?> blink;
  late Command3<void, PixelDie, Color, String> updateDieSettings;

  MainScreenViewModel(this._diWrapper) {
    // init
    load = Command0(_load)..execute();

    // theme
    toggleTheme = Command0(_toggleTheme);

    // ble
    startBleScan = Command0(_startBleScan);

    // ha config proxy
    setHaConfig = Command4(_setHaConfig);
    _haConfigSubscription = _diWrapper.haRepository.subscribeHaSettings().listen((conf) {
      _haConfig = conf;
      notifyListeners();
    });

    // rolling
    clearRollResultHistory = Command0(_clearRollResultHistory);
    setRollType = Command1(_setRollType);
    _rollResultsSubscription = _diWrapper.rollDomain.subscribeRollResults().listen((rollResult) {
      notifyListeners();
    });

    _rollStatusSubscription = _diWrapper.rollDomain.subscribeRollStatus().listen((rollResult) {
      notifyListeners();
    });

    // die control settings
    blink = Command3(_blink);
    updateDieSettings = Command3(_updateDieSettings);
  }

  // init
  Future<Result<void>> _load() async {
    try {
      final result = await _diWrapper.appRepository.getThemeMode();
      if (result.isValue && result.asValue != null) {
        themeMode = result.asValue!.value;
      }
      _haConfig = await _diWrapper.haRepository.getHaConfig();
      return result;
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

  RollType getRollType() {
    return _diWrapper.rollDomain.rollType;
  }

  // die control settings
  Map<String, Color> get blinkColors => _diWrapper.rollDomain.blinkColors;
  Future<Result<void>> _blink(Color blinkColor, PixelDie die, String? entityOverride) async {
    _diWrapper.rfController.blink(blinkColor, die);

    return Result.value(null);
  }

  // TODO: Refactor needed?  I'm not sure how the UI is getting notified about this?
  Stream<Map<String, PixelDie>> getDeviceStream() {
    return _diWrapper.rfController.getDeviceStream();
  }

  Future<Result<void>> _updateDieSettings(PixelDie die, Color blinkColor, String entity) async {
    _diWrapper.rollDomain.blinkColors[die.device.remoteId.str] = blinkColor;
    die.haEntityTargets = [entity];
    notifyListeners();
    return Result.value(null);
  }

  // Cleanup
  @override
  void dispose() {
    _haConfigSubscription.cancel();
    _rollResultsSubscription.cancel();
    _rollStatusSubscription.cancel();
    super.dispose();
  }
}
