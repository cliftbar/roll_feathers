import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';

/// Repository over the persisted set of [PixelProfile]s — the canonical
/// Repository pattern: abstracts the data store and presents an in-memory
/// collection view. No business logic; load/save/query only.
///
/// The interface lets the domain depend on an abstraction so tests can inject a
/// fake (pluggability via interface + DI, per `docs/architecture.md`).
abstract class PixelProfileRepository {
  Future<List<PixelProfile>> loadAll();
  Future<void> saveAll(List<PixelProfile> profiles);
  Future<void> upsert(PixelProfile profile);
  Future<void> delete(String id);
}

/// [PixelProfileRepository] backed by [SharedPreferences].
class SharedPrefsPixelProfileRepository implements PixelProfileRepository {
  static const _prefsKey = 'pixels_profiles';

  @override
  Future<List<PixelProfile>> loadAll() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((j) => PixelProfile.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAll(List<PixelProfile> profiles) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(
      _prefsKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  @override
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

  @override
  Future<void> delete(String id) async {
    final profiles = await loadAll();
    profiles.removeWhere((p) => p.id == id);
    await saveAll(profiles);
  }
}
