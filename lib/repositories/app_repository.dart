import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';

import 'package:roll_feathers/services/app_service.dart';

class AppRepository {
  AppRepository(this._service);

  final _themeModeController = StreamController<ThemeMode>.broadcast();

  final AppService _service;

  /// Get if dark mode is enabled
  Future<Result<ThemeMode>> getThemeMode() async {
    try {
      final value = await _service.getThemeMode();
      return Result.value(value);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Set dark mode
  Future<Result<void>> setThemeMode(ThemeMode mode) async {
    try {
      await _service.setThemeMode(mode);
      _themeModeController.add(mode);
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Stream that emits theme config changes.
  /// ViewModels should call [isDarkMode] to get the current theme setting.
  Stream<ThemeMode> observeThemeMode() => _themeModeController.stream;
}