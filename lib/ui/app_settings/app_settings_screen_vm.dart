import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';
import 'package:roll_feathers/domains/api_domain.dart';
import 'package:roll_feathers/domains/dddice_domain.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/ble/ble_repository.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/util/command.dart';
import 'package:roll_feathers/util/platform_info.dart';

class AppSettingsScreenViewModel extends ChangeNotifier {
  final AppRepository _appRepository;
  final BleRepository _bleRepository;
  final HaRepository _haRepository;
  final DddiceDomain _dddiceDomain;
  final DieDomain _dieDomain;
  final ApiDomain _apiDomain;
  final RuleEvaluator _ruleParser;
  final PlatformInfo _platform;

  /// Whether the app is running on the web, for view-layer presentation.
  bool get isWeb => _platform.isWeb;

  // init
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

  // dddice
  DddiceConfig _dddiceConfig = const DddiceConfig();
  StreamSubscription<DddiceActivationEvent>? _activationSubscription;
  String? _activationError;

  AppSettingsScreenViewModel(DiWrapper di)
      : _appRepository = di.appRepository,
        _bleRepository = di.bleRepository,
        _haRepository = di.haRepository,
        _dddiceDomain = di.dddiceDomain,
        _dieDomain = di.dieDomain,
        _apiDomain = di.apiDomain,
        _ruleParser = di.ruleParser,
        _platform = di.platformInfo {
    // init
    load = Command0(_load)..execute();

    // theme
    toggleTheme = Command0(_toggleTheme);

    // screen wake lock
    toggleKeepScreenOn = Command0(_toggleKeepScreenOn);
    _keepScreenOnSubscription = _appRepository.observeKeepScreenOn().listen((enabled) {
      keepScreenOn = enabled;
      WakelockPlus.toggle(enable: enabled);
      notifyListeners();
    });

    // layout orientation
    setDicePaneOrientation = Command1(_setDicePaneOrientation);
    _dicePaneOrientationSubscription = _appRepository.observeDicePaneOrientation().listen((orientation) {
      dicePaneOrientation = orientation;
      notifyListeners();
    });

    // webhooks
    toggleWebhooksEnabled = Command0(_toggleWebhooksEnabled);
    _webhooksEnabledSubscription = _appRepository.observeWebhooksEnabled().listen((enabled) {
      webhooksEnabled = enabled;
      notifyListeners();
    });

    // ble
    startBleScan = Command0(_startBleScan);
    _bleEnabledSubscription = _bleRepository.subscribeBleEnabled().listen((enabled) {
      _bleEnabled = enabled;
      notifyListeners();
    });
    _bleEnabled = _bleRepository.enabled && _bleRepository.supported;
    disconnectAllNonVirtualDice = Command0(_disconnectAllNonVirtualDice);

    // ha config proxy
    setHaConfig = Command4(_setHaConfig);
    _haConfigSubscription = _haRepository.subscribeHaSettings().listen((conf) {
      _haConfig = conf;
      notifyListeners();
    });
  }

  // init
  Future<Result<void>> _load() async {
    try {
      final themeResult = await _appRepository.getThemeMode();
      if (themeResult.isValue && themeResult.asValue != null) {
        themeMode = themeResult.asValue!.value;
      }

      final keepScreenOnResult = await _appRepository.getKeepScreenOn();
      if (keepScreenOnResult.isValue && keepScreenOnResult.asValue != null) {
        keepScreenOn = keepScreenOnResult.asValue!.value;
        WakelockPlus.toggle(enable: keepScreenOn);
      }

      final orientationResult = await _appRepository.getDicePaneOrientation();
      if (orientationResult.isValue && orientationResult.asValue != null) {
        dicePaneOrientation = orientationResult.asValue!.value;
      }

      final webhooksResult = await _appRepository.getWebhooksEnabled();
      if (webhooksResult.isValue && webhooksResult.asValue != null) {
        webhooksEnabled = webhooksResult.asValue!.value;
      }

      _haConfig = await _haRepository.getHaConfig();
      _dddiceConfig = await _dddiceDomain.getConfig();
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
      return await _appRepository.setThemeMode(themeMode);
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
      return await _appRepository.setKeepScreenOn(keepScreenOn);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  Future<Result<void>> _setDicePaneOrientation(DicePaneOrientation orientation) async {
    try {
      dicePaneOrientation = orientation;
      return await _appRepository.setDicePaneOrientation(orientation);
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
      return await _appRepository.setWebhooksEnabled(webhooksEnabled);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  // ble
  Future<Result<void>> _startBleScan() async {
    if (_scanInProgress) {
      return Result.value(null);
    }
    _scanInProgress = true;
    _scanProgressTimer?.cancel();
    notifyListeners();
    try {
      await _bleRepository.scan(services: [pixelsService], namePrefix: ['GoDice_']);
      if (_platform.isWeb) {
        _scanInProgress = false;
        notifyListeners();
      } else {
        _scanProgressTimer = Timer(const Duration(seconds: 6), () {
          _scanInProgress = false;
          notifyListeners();
        });
      }
      return Result.value(null);
    } catch (e) {
      debugPrint('[BLE] scan error: $e');
      _scanInProgress = false;
      notifyListeners();
      return Result.error(Exception(e.toString()));
    }
  }

  Future<Result<void>> _disconnectAllNonVirtualDice() async {
    await _dieDomain.disconnectAllNonVirtualDice();
    notifyListeners();
    return Result.value(null);
  }

  bool bleIsEnabled() => _bleEnabled;

  List<String> getIpAddresses() => _apiDomain.getIpAddresses();

  // ha config proxy
  HaConfig getHaConfig() => _haConfig;

  Future<Result<void>> _setHaConfig(bool enabled, String url, String token, String entity) async {
    _haRepository.updateSettings(enabled: enabled, url: url, token: token, entity: entity);
    return Result.value(null);
  }

  // dddice
  DddiceConfig getDddiceConfig() => _dddiceConfig;
  String? get activationError => _activationError;

  Future<void> saveDddiceConfig(DddiceConfig config) async {
    await _dddiceDomain.saveConfig(config);
    _dddiceConfig = config;
    notifyListeners();
  }

  Future<List<DddiceRoom>> dddiceListRooms() =>
      _dddiceDomain.listRooms(_dddiceConfig.token);

  Future<List<DddiceTheme>> dddiceListThemes() =>
      _dddiceDomain.listThemes(_dddiceConfig.token);

  Future<bool> dddiceSignInAsGuest() async {
    final success = await _dddiceDomain.signInAsGuest();
    if (success) {
      _dddiceConfig = await _dddiceDomain.getConfig();
      notifyListeners();
    }
    return success;
  }

  Future<DddiceActivationCode?> dddiceStartActivation() async {
    _activationSubscription?.cancel();
    _activationError = null;
    final code = await _dddiceDomain.startActivation();
    if (code == null) return null;

    _activationSubscription = _dddiceDomain.activationEvents.listen(
      (event) {
        switch (event) {
          case DddiceActivationComplete(:final config):
            _dddiceConfig = config;
            _activationError = null;
            _activationSubscription = null;
            notifyListeners();
          case DddiceActivationError(:final message):
            _activationError = message;
            notifyListeners();
        }
      },
    );
    return code;
  }

  Future<void> dddiceCancelActivation() async {
    _activationSubscription?.cancel();
    _activationSubscription = null;
    _activationError = null;
    await _dddiceDomain.cancelActivation();
    notifyListeners();
  }

  Future<void> dddiceSignOut() async {
    _activationSubscription?.cancel();
    _activationSubscription = null;
    _activationError = null;
    await _dddiceDomain.signOut();
    _dddiceConfig = const DddiceConfig();
    notifyListeners();
  }

  // Scripts
  String? saveError;

  List<RuleScript> getRuleScripts() => _ruleParser.getRules();

  List<RuleScript> getHiddenDefaultRules() => _ruleParser.getHiddenDefaultRules();

  bool isUserOnlyRule(String name) => _ruleParser.isUserOnlyRule(name);

  Future<void> addRuleScript(String script, {bool enabled = true}) async {
    saveError = null;
    try {
      await _ruleParser.addRuleScript(script, enabled: enabled);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> toggleRuleScript(String name, bool enabled) async {
    saveError = null;
    try {
      await _ruleParser.toggleRuleScript(name, enabled);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> reorderRules(int idxFrom, int idxTo) async {
    saveError = null;
    try {
      await _ruleParser.reorderRules(idxFrom, idxTo);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> removeRule(int idx) async {
    saveError = null;
    try {
      await _ruleParser.removeRule(idx);
    } catch (e) {
      saveError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> unhideRule(String name) async {
    saveError = null;
    try {
      await _ruleParser.unhideRule(name);
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
    _activationSubscription?.cancel();
    _appRepository.setKeepScreenOn(false);
    super.dispose();
  }
}
