import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:roll_feathers/repositories/app_repository.dart';

import '../util/command.dart';

class RollFeathersViewModel extends ChangeNotifier {
  RollFeathersViewModel._(this._appRepository) {
    _subscription = _appRepository.observeThemeMode().listen((mode) {
      _themeMode = mode;
      notifyListeners();
    });
  }

  static Future<RollFeathersViewModel> create(AppRepository appRepo) async {
    var ret = RollFeathersViewModel._(appRepo);

    await ret._load();

    return ret;
}

  final AppRepository _appRepository;
  StreamSubscription<ThemeMode>? _subscription;

  late ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

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
    _subscription?.cancel();
    super.dispose();
  }
}