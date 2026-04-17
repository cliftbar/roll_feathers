import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/util/command.dart';

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

  // layout orientation
  DicePaneOrientation dicePaneOrientation = DicePaneOrientation.auto;
  late Command1<void, DicePaneOrientation> setDicePaneOrientation;
  late StreamSubscription<DicePaneOrientation> _dicePaneOrientationSubscription;

  // webhooks
  bool webhooksEnabled = true;
  late Command0 toggleWebhooksEnabled;
  late StreamSubscription<bool> _webhooksEnabledSubscription;

  // ble
  bool _bleEnabled = false;
  late Command0 startBleScan;
  late StreamSubscription<bool> _bleEnabledSubscription;
  late Command0<void> disconnectAllNonVirtualDice;
  bool _scanInProgress = false;
  bool get isScanning => _scanInProgress;
  Timer? _scanProgressTimer;

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

    // layout orientation
    setDicePaneOrientation = Command1(_setDicePaneOrientation);
    _dicePaneOrientationSubscription = _diWrapper.appRepository.observeDicePaneOrientation().listen((orientation) {
      dicePaneOrientation = orientation;
      notifyListeners();
    });

    // webhooks
    toggleWebhooksEnabled = Command0(_toggleWebhooksEnabled);
    _webhooksEnabledSubscription = _diWrapper.appRepository.observeWebhooksEnabled().listen((enabled) {
      webhooksEnabled = enabled;
      notifyListeners();
    });

    // ble
    startBleScan = Command0(_startBleScan);
    _bleEnabledSubscription = _diWrapper.bleRepository.subscribeBleEnabled().listen((enabled) {
      _bleEnabled = enabled;
      notifyListeners();
    });
    // initialize from current repo state; stream will keep it updated
    _bleEnabled = _diWrapper.bleRepository.enabled && _diWrapper.bleRepository.supported;
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

      final orientationResult = await _diWrapper.appRepository.getDicePaneOrientation();
      if (orientationResult.isValue && orientationResult.asValue != null) {
        dicePaneOrientation = orientationResult.asValue!.value;
      }

      final webhooksResult = await _diWrapper.appRepository.getWebhooksEnabled();
      if (webhooksResult.isValue && webhooksResult.asValue != null) {
        webhooksEnabled = webhooksResult.asValue!.value;
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

  Future<Result<void>> _setDicePaneOrientation(DicePaneOrientation orientation) async {
    try {
      dicePaneOrientation = orientation;
      return await _diWrapper.appRepository.setDicePaneOrientation(orientation);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  // webhooks
  Future<Result<void>> _toggleWebhooksEnabled() async {
    try {
      webhooksEnabled = !webhooksEnabled;
      return await _diWrapper.appRepository.setWebhooksEnabled(webhooksEnabled);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  // ble
  Future<Result<void>> _startBleScan() async {
    if (_scanInProgress) {
      // Debounce rapid taps
      return Result.value(null);
    }
    _scanInProgress = true;
    _scanProgressTimer?.cancel();
    notifyListeners();
    try {
      // Put filters back on Web as requested; use Pixels service by default.
      // Other platforms can also use the same filter.
      await _diWrapper.bleRepository.scan(services: [pixelsService], namePrefix: ['GoDice_']);
      if (kIsWeb) {
        // On web, scan() blocks until the browser dialog closes and the device
        // connects — by the time it returns the scan is already complete.
        _scanInProgress = false;
        notifyListeners();
      } else {
        // On native, scan() returns immediately and runs a background timer.
        // Keep the spinner visible for the same window so the user sees progress.
        _scanProgressTimer = Timer(const Duration(seconds: 6), () {
          _scanInProgress = false;
          notifyListeners();
        });
      }
      return Result.value(null);
    } catch (e) {
      // On Web, repository may suppress rethrow; this catch is mostly for native.
      debugPrint('[BLE] scan error: $e');
      _scanInProgress = false;
      notifyListeners();
      // Do not rethrow; surface as a Result error so UI remains responsive.
      return Result.error(Exception(e.toString()));
    }
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
  String? saveError;

  List<RuleScript> getRuleScripts() {
    return _diWrapper.ruleParser.getRules();
  }

  List<RuleScript> getHiddenDefaultRules() {
    return _diWrapper.ruleParser.getHiddenDefaultRules();
  }

  bool isUserOnlyRule(String name) {
    return _diWrapper.ruleParser.isUserOnlyRule(name);
  }

  Future<void> addRuleScript(String script, {bool enabled = true}) async {
    saveError = null;
    try {
      await _diWrapper.ruleParser.addRuleScript(script, enabled: enabled);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> toggleRuleScript(String name, bool enabled) async {
    saveError = null;
    try {
      await _diWrapper.ruleParser.toggleRuleScript(name, enabled);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> reorderRules(int idxFrom, int idxTo) async {
    saveError = null;
    try {
      await _diWrapper.ruleParser.reorderRules(idxFrom, idxTo);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> removeRule(int idx) async {
    saveError = null;
    try {
      await _diWrapper.ruleParser.removeRule(idx);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> unhideRule(String name) async {
    saveError = null;
    try {
      await _diWrapper.ruleParser.unhideRule(name);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }


  // Cleanup
  @override
  void dispose() {
    _scanProgressTimer?.cancel();
    _haConfigSubscription.cancel();
    _keepScreenOnSubscription.cancel();
    _webhooksEnabledSubscription.cancel();
    _bleEnabledSubscription.cancel();
    _dicePaneOrientationSubscription.cancel();
    _diWrapper.appRepository.setKeepScreenOn(false);
    super.dispose();
  }
}
