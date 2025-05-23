import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/services/home_assistant/ha_config_service.dart';
import 'package:roll_feathers/util/command.dart';

class MainScreenViewModel extends ChangeNotifier {
  final AppRepository _appRepository;
  final HaRepository _haRepository;

  late HaConfig _haConfig;
  ThemeMode themeMode = ThemeMode.system;

  late Command0 load;
  late Command0 toggleTheme;
  late Command2<void, Color, PixelDie> blink;
  late Command4<void, bool, String, String, String> setHaConfig;

  late StreamSubscription<HaConfig> _haConfigSubscription;

  MainScreenViewModel(this._appRepository, this._haRepository) {
    load = Command0(_load)..execute();
    toggleTheme = Command0(_toggleTheme);
    blink = Command2(_blink);
    setHaConfig = Command4(_setHaConfig);

    // why is this here, but we're still getting theme notifys?
    _haConfigSubscription = _haRepository.subscribeHaSettings().listen((conf) {
      _haConfig = conf;
      notifyListeners();
    });
  }

  ThemeMode get getThemeMode => themeMode;

  HaConfig get getHaConfig => _haConfig;

  /// Load the current theme setting from the repository
  Future<Result<void>> _load() async {
    try {
      final result = await _appRepository.getThemeMode();
      if (result.isValue && result.asValue != null) {
        themeMode = result.asValue!.value;
      }
      _haConfig = await _haRepository.getHaConfig();
      return result;
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  /// Toggle the theme setting
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

  Future<Result<void>> _blink(Color blinkColor, PixelDie die) async {
    var blinker = BlinkMessage(blinkColor: blinkColor);
    String? entity = die.haEntityTargets.firstOrNull;
    _haRepository.blinkEntity(entity: entity, blink: blinker);

    return Result.value(null);
  }

  Future<Result<void>> _setHaConfig(bool enabled, String url, String token, String entity) async {
    _haRepository.updateSettings(enabled: enabled, url: url, token: token, entity: entity);

    return Result.value(null);
  }

  @override
  void dispose() {
    _haConfigSubscription.cancel();
    super.dispose();
  }
}
