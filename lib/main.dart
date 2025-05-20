import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:roll_feathers/config.dart';
import 'package:roll_feathers/ui/roll_feathers_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.info, color: true);

  // Load the theme preference before running the app
  final prefs = await SharedPreferences.getInstance();
  final themeIndex = prefs.getInt(themeKey) ?? ThemeMode.dark.index;
  final initialThemeMode = ThemeMode.values[themeIndex];

  runApp(RollFeatherApp(initialThemeMode: initialThemeMode));
}
