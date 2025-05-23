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
    final prefs = await SharedPreferences.getInstance();

    bool enabled = prefs.getBool(haEnabledKey) ?? false;
    String url = prefs.getString(kaUrlKey) ?? "";
    String token = prefs.getString(haTokenKey) ?? "";
    String entity = prefs.getString(haEntityKey) ?? "";

    return HaConfig(enabled: enabled, url: url, token: token, entity: entity);
  }

  Future<bool> setConfig(HaConfig conf) async {
    final prefs = await SharedPreferences.getInstance();

    List<bool> sets = await Future.wait([
      prefs.setBool(haEnabledKey, conf.enabled),
      prefs.setString(kaUrlKey, conf.url),
      prefs.setString(haTokenKey, conf.token),
      prefs.setString(haEntityKey, conf.entity),
    ]);

    return !sets.contains(false);
  }
}
