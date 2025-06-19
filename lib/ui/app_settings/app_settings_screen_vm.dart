import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../di/di.dart';
import '../../dice_sdks/pixels.dart';
import '../../services/home_assistant/ha_config_service.dart';
import '../../util/command.dart';

class AppSettingsScreenViewModel extends ChangeNotifier {
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
  bool _bleEnabled = false;
  late Command0 startBleScan;
  late StreamSubscription<bool> _bleEnabledSubscription;
  late Command0<void> disconnectAllNonVirtualDice;

  // ha config proxy
  late HaConfig _haConfig;
  late Command4<void, bool, String, String, String> setHaConfig;
  late StreamSubscription<HaConfig> _haConfigSubscription;

  AppSettingsScreenViewModel(this._diWrapper) {
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
    _bleEnabled = _diWrapper.bleRepository.enabled && _diWrapper.bleRepository.enabled;
    disconnectAllNonVirtualDice = Command0(_disconnectAllNonVirtualDice);

    // ha config proxy
    setHaConfig = Command4(_setHaConfig);
    _haConfigSubscription = _diWrapper.haRepository.subscribeHaSettings().listen((conf) {
      _haConfig = conf;
      notifyListeners();
    });
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

  Future<Result<void>> _disconnectAllNonVirtualDice() async {
    await _diWrapper.dieDomain.disconnectAllNonVirtualDice();
    notifyListeners();
    return Result.value(null);
  }

  bool bleIsEnabled() {
    return _bleEnabled;
  }

  List<String> getIpAddresses() {
    return _diWrapper.apiDomain.getIpAddresses();
  }

  // ha config proxy
  HaConfig getHaConfig() => _haConfig;

  Future<Result<void>> _setHaConfig(bool enabled, String url, String token, String entity) async {
    _diWrapper.haRepository.updateSettings(enabled: enabled, url: url, token: token, entity: entity);

    return Result.value(null);
  }

  // Scripts
  List<RuleScript> getRuleScripts() {
    return _diWrapper.rollDomain.ruleParser.getRules();
  }

  void addRuleScript(String script, {bool enabled = true}) {
    _diWrapper.rollDomain.ruleParser.addRuleScript(script, enabled: enabled);
    notifyListeners();
  }
  void toggleRuleScript(String name, bool enabled) {
    _diWrapper.rollDomain.ruleParser.toggleRuleScript(name, enabled);
    notifyListeners();
  }

  void reorderRules(int idxFrom, int idxTo) {
    _diWrapper.rollDomain.ruleParser.reorderRules(idxFrom, idxTo);
    notifyListeners();
  }

  void removeRule(int idx) {
    _diWrapper.rollDomain.ruleParser.removeRule(idx);
    notifyListeners();
  }


  // Cleanup
  @override
  void dispose() {
    _haConfigSubscription.cancel();
    _keepScreenOnSubscription.cancel();
    _bleEnabledSubscription.cancel();
    _diWrapper.appRepository.setKeepScreenOn(false);
    super.dispose();
  }
}
