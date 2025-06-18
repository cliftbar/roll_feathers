import 'package:shared_preferences/shared_preferences.dart';

class HaConfig {
  final bool enabled;
  final String url;
  final String token;
  final String entity;

  const HaConfig({required this.enabled, required this.url, required this.token, required this.entity});
}

class HaConfigService {
  static String haEnabledKey = "ha.enabled";
  static String haEntityKey = "ha.entity";
  static String kaUrlKey = "ha.url";
  static String haTokenKey = "ha.token";

  Future<HaConfig> getConfig() async {
    final SharedPreferencesAsync prefs = SharedPreferencesAsync();

    bool enabled = await prefs.getBool(haEnabledKey) ?? false;
    String url = await prefs.getString(kaUrlKey) ?? "";
    String token = await prefs.getString(haTokenKey) ?? "";
    String entity = await prefs.getString(haEntityKey) ?? "";

    return HaConfig(enabled: enabled, url: url, token: token, entity: entity);
  }

  Future<bool> setConfig(HaConfig conf) async {
    final SharedPreferencesAsync prefs = SharedPreferencesAsync();

    await prefs.setBool(haEnabledKey, conf.enabled);
    await prefs.setString(kaUrlKey, conf.url);
    await prefs.setString(haTokenKey, conf.token);
    await prefs.setString(haEntityKey, conf.entity);

    return true;
  }
}
