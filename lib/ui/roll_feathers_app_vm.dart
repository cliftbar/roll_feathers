import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:roll_feathers/repositories/app_repository.dart';

class RollFeathersAppVM extends ChangeNotifier {
  final AppRepository _appRepository;
  StreamSubscription<ThemeMode>? _themeSubscription;

  late ThemeMode _themeMode;

  RollFeathersAppVM._(this._appRepository) {
    _themeSubscription = _appRepository.observeThemeMode().listen((mode) {
      _themeMode = mode;
      notifyListeners();
    });
  }

  ThemeMode get themeMode => _themeMode;

  static Future<RollFeathersAppVM> create(AppRepository appRepo) async {
    var ret = RollFeathersAppVM._(appRepo);

    await ret._load();

    return ret;
  }

  Future<Result<void>> _load() async {
    final result = await _appRepository.getThemeMode();
    if (result.isValue && result.asValue != null) {
      _themeMode = result.asValue!.value;
    } else {
      // handle error
      print(result.asError?.error);
    }
    notifyListeners();
    return Result.value(null);
  }

  @override
  void dispose() {
    _themeSubscription?.cancel();
    super.dispose();
  }
}
