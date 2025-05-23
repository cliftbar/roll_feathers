import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/repositories/app_repository.dart';

import 'package:roll_feathers/util/command.dart';

class MainScreenViewModel extends ChangeNotifier {
  final AppRepository _appRepository;

  MainScreenViewModel(this._appRepository) {
    load = Command0(_load)..execute();
    toggleTheme = Command0(_toggleTheme);
  }

  late Command0 load;
  late Command0 toggleTheme;

  ThemeMode themeMode = ThemeMode.system;
  ThemeMode get getThemeMode => themeMode;

  /// Load the current theme setting from the repository
  Future<Result<void>> _load() async {
    try {
      final result = await _appRepository.getThemeMode();
      if (result.isValue && result.asValue != null) {
        themeMode = result.asValue!.value;
      }
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
}