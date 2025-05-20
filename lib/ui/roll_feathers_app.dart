import 'package:flutter/material.dart';
import 'package:roll_feathers/config.dart';
import 'package:roll_feathers/ui/main_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Handles theming
// launches main screen
class RollFeatherApp extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const RollFeatherApp({super.key, required this.initialThemeMode});

  @override
  State<RollFeatherApp> createState() => _RollFeatherAppState();
}

class _RollFeatherAppState extends State<RollFeatherApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    // Use the preloaded theme mode
    _themeMode = widget.initialThemeMode;
  }

  // Save theme preference
  Future<void> _saveThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(themeKey, _themeMode.index);
  }

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      _saveThemePreference(); // Save the preference when theme changes
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: RollFeatherMainScreenWidget(toggleTheme: toggleTheme, themeMode: _themeMode),
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
    );
  }
}
