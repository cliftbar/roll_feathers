import 'package:shared_preferences/shared_preferences.dart';

class DddiceConfig {
  final bool enabled;
  final String token;
  final bool isGuest;
  final bool needsReauth;
  final String roomSlug;
  final String roomName;
  final String themeId;
  final String themeName;

  const DddiceConfig({
    this.enabled = false,
    this.token = '',
    this.isGuest = false,
    this.needsReauth = false,
    this.roomSlug = '',
    this.roomName = '',
    this.themeId = '',
    this.themeName = '',
  });

  bool get isAuthenticated => token.isNotEmpty;

  DddiceConfig copyWith({
    bool? enabled,
    String? token,
    bool? isGuest,
    bool? needsReauth,
    String? roomSlug,
    String? roomName,
    String? themeId,
    String? themeName,
  }) {
    return DddiceConfig(
      enabled: enabled ?? this.enabled,
      token: token ?? this.token,
      isGuest: isGuest ?? this.isGuest,
      needsReauth: needsReauth ?? this.needsReauth,
      roomSlug: roomSlug ?? this.roomSlug,
      roomName: roomName ?? this.roomName,
      themeId: themeId ?? this.themeId,
      themeName: themeName ?? this.themeName,
    );
  }
}

class DddiceConfigService {
  static const _enabledKey = 'dddice_enabled';
  static const _tokenKey = 'dddice_token';
  static const _isGuestKey = 'dddice_is_guest';
  static const _needsReauthKey = 'dddice_needs_reauth';
  static const _roomSlugKey = 'dddice_room_slug';
  static const _roomNameKey = 'dddice_room_name';
  static const _themeIdKey = 'dddice_theme_id';
  static const _themeNameKey = 'dddice_theme_name';

  Future<DddiceConfig> getConfig() async {
    final prefs = SharedPreferencesAsync();
    return DddiceConfig(
      enabled: await prefs.getBool(_enabledKey) ?? false,
      token: await prefs.getString(_tokenKey) ?? '',
      isGuest: await prefs.getBool(_isGuestKey) ?? false,
      needsReauth: await prefs.getBool(_needsReauthKey) ?? false,
      roomSlug: await prefs.getString(_roomSlugKey) ?? '',
      roomName: await prefs.getString(_roomNameKey) ?? '',
      themeId: await prefs.getString(_themeIdKey) ?? '',
      themeName: await prefs.getString(_themeNameKey) ?? '',
    );
  }

  Future<void> setConfig(DddiceConfig config) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_enabledKey, config.enabled);
    await prefs.setString(_tokenKey, config.token);
    await prefs.setBool(_isGuestKey, config.isGuest);
    await prefs.setBool(_needsReauthKey, config.needsReauth);
    await prefs.setString(_roomSlugKey, config.roomSlug);
    await prefs.setString(_roomNameKey, config.roomName);
    await prefs.setString(_themeIdKey, config.themeId);
    await prefs.setString(_themeNameKey, config.themeName);
  }

  Future<void> setNeedsReauth(bool value) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_needsReauthKey, value);
  }

  Future<void> signOut() async => setConfig(const DddiceConfig());
}
