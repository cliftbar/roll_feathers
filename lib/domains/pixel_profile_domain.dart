import 'package:uuid/uuid.dart';

import 'package:roll_feathers/core/pixels/animation_import.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/repositories/pixels/pixel_profile_repository.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';

/// Orchestrates Pixels profile use-cases: CRUD, duplication, animation import,
/// and die-bound preview/flash + on-die status.
///
/// This is the only layer the profile UI talks to. It is app-scoped and holds
/// the data [PixelProfileRepository]; die-bound operations take a per-die
/// [PixelDieService] (the active die's service), per the architecture's
/// "app-scoped domain + per-die service passed in" decision.
class PixelProfileDomain {
  PixelProfileDomain(this._repo);

  final PixelProfileRepository _repo;
  static const _uuid = Uuid();

  // ─── Profile data (via repository) ──────────────────────────────────────────

  Future<List<PixelProfile>> loadProfiles() => _repo.loadAll();

  Future<void> save(PixelProfile profile) => _repo.upsert(profile);

  Future<void> delete(String id) => _repo.delete(id);

  /// The built-in profile catalog (from the repository, not imported directly).
  List<BuiltinProfile> builtins() => _repo.builtins();

  // ─── Pure profile/animation logic ───────────────────────────────────────────

  /// Deep-clones [profile] with a fresh id and a "(copy)" name, ready to open in
  /// the editor. Does not persist — the caller saves after any edits.
  PixelProfile duplicate(PixelProfile profile) => PixelProfile.fromJson({
    ...profile.toJson(),
    'id': _uuid.v4(),
    'name': '${profile.name} (copy)',
  });

  /// Stamps [template] (e.g. a built-in's `build()` result, or a blank) with a
  /// fresh id so it becomes a new user profile.
  PixelProfile newFromTemplate(PixelProfile template) => PixelProfile(
    id: _uuid.v4(),
    name: template.name,
    brightness: template.brightness,
    animations: template.animations,
    rules: template.rules,
  );

  /// Resolves an animation import (chosen animation + its transitive sibling
  /// references, remapped for [destLen]). Delegates to the pure core helper.
  List<PixelAnimation> importAnimation(List<PixelAnimation> source, int index, int destLen) =>
      resolveAnimationImport(source, index, destLen);

  /// The die-stored hash a profile must match to be "on the die".
  int profileHash(PixelProfile profile) => PixelDataSet(profile).computeHash().toUnsigned(32);

  /// Whether [profile] is the one currently flashed on the die behind [service].
  bool isOnDie(PixelProfile profile, PixelDieService service) {
    final dieHash = service.currentDataSetHash?.toUnsigned(32);
    return dieHash != null && dieHash == profileHash(profile);
  }

  // ─── Die-bound operations (via the active die's service) ─────────────────────

  /// Flash [profile] to the die permanently.
  Future<void> flash(PixelDieService service, PixelProfile profile) =>
      service.transferProfile(profile);

  /// Preview the animation at [animIndex] of [profile] on the die (RAM, once).
  Future<void> preview(PixelDieService service, PixelProfile profile, int animIndex) =>
      service.previewProfileAnimation(profile, animIndex);
}
