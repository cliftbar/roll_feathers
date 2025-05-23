// datastore access
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppService {
  static String themeKey = 'theme_mode';

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(themeKey, mode.index);
  }

  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(themeKey) ?? ThemeMode.system.index;
    final mode = ThemeMode.values[themeIndex];
    return mode;
  }
}
