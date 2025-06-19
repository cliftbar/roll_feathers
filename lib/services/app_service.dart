// datastore access
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppService {
  static String themeKey = 'theme_mode';
  static String keepScreenOnKey = 'keep_screen_on';
  static String ruleScriptsKey = 'rule_scripts';

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

  Future<void> setKeepScreenOn(bool keepScreenOn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keepScreenOnKey, keepScreenOn);
  }

  Future<bool> getKeepScreenOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keepScreenOnKey) ?? false;
  }

  Future<List<String>> getSavedScripts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(ruleScriptsKey) ?? [];
  }

  Future<void> setSavedScripts(List<String> scripts) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(ruleScriptsKey, scripts);
  }
}
