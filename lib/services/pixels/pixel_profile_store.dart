import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

class PixelProfileStore {
  static const _prefsKey = 'pixels_profiles';

  Future<List<PixelProfile>> loadAll() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((j) => PixelProfile.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<PixelProfile> profiles) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      _prefsKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> upsert(PixelProfile profile) async {
    final profiles = await loadAll();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await saveAll(profiles);
  }

  Future<void> delete(String id) async {
    final profiles = await loadAll();
    profiles.removeWhere((p) => p.id == id);
    await saveAll(profiles);
  }
}
