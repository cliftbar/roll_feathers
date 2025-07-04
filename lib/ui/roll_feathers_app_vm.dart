import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/di/di.dart';

class RollFeathersAppVM extends ChangeNotifier {
  final _log = Logger("RollFeathersAppVM");
  final DiWrapper _diWrapper;
  StreamSubscription<ThemeMode>? _themeSubscription;

  late ThemeMode _themeMode;

  RollFeathersAppVM._(this._diWrapper) {
    _themeSubscription = _diWrapper.appRepository.observeThemeMode().listen((mode) {
      _themeMode = mode;
      notifyListeners();
    });
  }

  ThemeMode get themeMode => _themeMode;

  static Future<RollFeathersAppVM> create(DiWrapper di) async {
    var ret = RollFeathersAppVM._(di);

    await ret._load();

    return ret;
  }

  Future<Result<void>> _load() async {
    final result = await _diWrapper.appRepository.getThemeMode();
    if (result.isValue && result.asValue != null) {
      _themeMode = result.asValue!.value;
    } else {
      // handle error
      _log.severe(result.asError?.error);
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
