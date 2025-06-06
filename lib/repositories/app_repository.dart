import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/services/app_service.dart';

class AppRepository {
  AppRepository(this._service);

  final _themeModeController = StreamController<ThemeMode>.broadcast();
  final _keepScreenOnController = StreamController<bool>.broadcast();

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

  /// Get if screen should be kept on
  Future<Result<bool>> getKeepScreenOn() async {
    try {
      final value = await _service.getKeepScreenOn();
      return Result.value(value);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Set if screen should be kept on
  Future<Result<void>> setKeepScreenOn(bool keepScreenOn) async {
    try {
      await _service.setKeepScreenOn(keepScreenOn);
      _keepScreenOnController.add(keepScreenOn);
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Stream that emits screen wake lock setting changes.
  Stream<bool> observeKeepScreenOn() => _keepScreenOnController.stream;
}
