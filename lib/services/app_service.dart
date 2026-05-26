// datastore access
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roll_feathers/dice_sdks/dice_sdks.dart';

enum DicePaneOrientation {
  auto,
  horizontal,
  vertical,
}

/// Per-die settings persisted under the die's UUID.
class DieSettings {
  String? friendlyName;
  Color? blinkColor;
  List<String> haEntityTargets;
  String? faceTypeName;
  bool rollingFlashEnabled;
  Color? rollingFlashColor;
  RollingFlashPreset rollingFlashPreset;

  DieSettings({
    this.friendlyName,
    this.blinkColor,
    this.haEntityTargets = const [],
    this.faceTypeName,
    this.rollingFlashEnabled = false,
    this.rollingFlashColor,
    this.rollingFlashPreset = RollingFlashPreset.strobe,
  });

  Map<String, dynamic> toJson() => {
    if (friendlyName != null) 'friendlyName': friendlyName,
    if (blinkColor != null) 'blinkColor': blinkColor!.toARGB32(),
    'haEntityTargets': haEntityTargets,
    if (faceTypeName != null) 'faceTypeName': faceTypeName,
    'rollingFlashEnabled': rollingFlashEnabled,
    if (rollingFlashColor != null) 'rollingFlashColor': rollingFlashColor!.toARGB32(),
    'rollingFlashPreset': rollingFlashPreset.name,
  };

  factory DieSettings.fromJson(Map<String, dynamic> json) {
    return DieSettings(
      friendlyName: json['friendlyName'] as String?,
      blinkColor: json['blinkColor'] != null ? Color(json['blinkColor'] as int) : null,
      haEntityTargets: (json['haEntityTargets'] as List?)?.cast<String>() ?? [],
      faceTypeName: json['faceTypeName'] as String?,
      rollingFlashEnabled: json['rollingFlashEnabled'] as bool? ?? false,
      rollingFlashColor: json['rollingFlashColor'] != null ? Color(json['rollingFlashColor'] as int) : null,
      rollingFlashPreset: RollingFlashPreset.values.firstWhere(
        (p) => p.name == json['rollingFlashPreset'],
        orElse: () => RollingFlashPreset.strobe,
      ),
    );
  }
}

class AppService {
  static String themeKey = 'theme_mode';
  static String keepScreenOnKey = 'keep_screen_on';
  static String ruleScriptsKey = 'rule_scripts';
  static String ruleOrderKey = 'rule_order';
  static String hiddenRuleNamesKey = 'hidden_rule_names';
  static String dicePaneOrientationKey = 'dice_pane_orientation';
  static String webhooksEnabledKey = 'webhooks_enabled';

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
    await prefs.setStringList(ruleScriptsKey, scripts);
  }

  Future<List<String>> getRuleOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(ruleOrderKey) ?? [];
  }

  Future<void> setRuleOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(ruleOrderKey, order);
  }

  Future<List<String>> getHiddenRuleNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(hiddenRuleNamesKey) ?? [];
  }

  Future<void> setHiddenRuleNames(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(hiddenRuleNamesKey, names);
  }

  Future<void> setDicePaneOrientation(DicePaneOrientation orientation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(dicePaneOrientationKey, orientation.index);
  }

  Future<DicePaneOrientation> getDicePaneOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(dicePaneOrientationKey) ?? DicePaneOrientation.auto.index;
    return DicePaneOrientation.values[index];
  }

  Future<void> setWebhooksEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(webhooksEnabledKey, enabled);
  }

  Future<bool> getWebhooksEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(webhooksEnabledKey) ?? true;
  }

  static String _dieSettingsKey(String dieId) => 'die_settings_$dieId';

  Future<DieSettings?> getDieSettings(String dieId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dieSettingsKey(dieId));
    if (raw == null) return null;
    return DieSettings.fromJson(Map<String, dynamic>.from(
        const JsonDecoder().convert(raw) as Map));
  }

  Future<void> saveDieSettings(String dieId, DieSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dieSettingsKey(dieId),
        const JsonEncoder().convert(settings.toJson()));
  }
}
