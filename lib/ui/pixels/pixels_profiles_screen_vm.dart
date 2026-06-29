import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/util/command.dart';

/// ViewModel for [PixelsProfilesScreen] (MVVM + Command — see docs/architecture).
///
/// Takes the specific deps it needs (domain + the active die's service), not the
/// whole DiWrapper. Commands give single-flight + error capture; success text
/// and per-row progress live in plain fields ([statusMessage]/[transferringId]).
class PixelsProfilesScreenViewModel extends ChangeNotifier {
  PixelsProfilesScreenViewModel(this.domain, this.dieService, this.dieName) {
    builtins = domain.builtins();
    _builtinHashes = {
      for (final p in builtins) p.name: domain.profileHash(p.build(dieType)),
    };
    _dieHash = dieService.currentDataSetHash;
    load = Command0(_load)..execute();
    flashBuiltin = Command1(_flashBuiltin);
    flashProfile = Command1(_flashProfile);
    previewAnimation = Command3(_previewAnimation);
    deleteProfile = Command1(_deleteProfile);
    saveEdited = Command1(_saveEdited);
  }

  final PixelProfileDomain domain;
  final PixelDieService dieService;
  final String dieName;

  /// The connected die's type, for building die-type-correct built-ins.
  PixelDieType get dieType => dieService.dieType;

  /// The built-in profile catalog (via the domain, not imported directly).
  late final List<BuiltinProfile> builtins;

  late final Command0 load;
  late final Command1<void, BuiltinProfile> flashBuiltin;
  late final Command1<void, PixelProfile> flashProfile;
  late final Command3<void, PixelProfile, String, int> previewAnimation;
  late final Command1<void, PixelProfile> deleteProfile;
  late final Command1<void, PixelProfile> saveEdited;

  List<PixelProfile> _profiles = [];
  List<PixelProfile> get profiles => _profiles;

  Map<String, int> _hashes = {};
  late final Map<String, int> _builtinHashes;
  int? _dieHash;

  bool _loading = true;
  bool get loading => _loading;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  /// Id (built-in name or profile id) currently transferring, for a per-row
  /// spinner. Null when idle.
  String? _transferringId;
  String? get transferringId => _transferringId;

  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  bool isBuiltinOnDie(BuiltinProfile p) =>
      _dieHash != null && _builtinHashes[p.name] == _dieHash!.toUnsigned(32);

  bool isProfileOnDie(PixelProfile p) =>
      _dieHash != null && _hashes[p.id]?.toUnsigned(32) == _dieHash!.toUnsigned(32);

  /// Pure helpers used by the widget to build the profile it pushes to the editor.
  PixelProfile duplicate(PixelProfile p) => domain.duplicate(p);
  PixelProfile newFromTemplate(PixelProfile t) => domain.newFromTemplate(t);

  Future<Result<void>> _load() async {
    try {
      final profiles = await domain.loadProfiles();
      _profiles = profiles;
      _hashes = {for (final p in profiles) p.id: domain.profileHash(p)};
      _loading = false;
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      notifyListeners();
    }
  }

  Future<Result<void>> _flashBuiltin(BuiltinProfile preset) async {
    _transferringId = preset.name;
    _statusMessage = null;
    notifyListeners();
    try {
      await domain.flash(dieService, preset.build(dieType));
      _dieHash = _builtinHashes[preset.name];
      _statusMessage = '✓ "${preset.name}" flashed to die';
      return Result.value(null);
    } catch (e) {
      _statusMessage = 'Transfer failed: $e';
      return Result.error(Exception('$e'));
    } finally {
      _transferringId = null;
      notifyListeners();
    }
  }

  Future<Result<void>> _flashProfile(PixelProfile profile) async {
    _transferringId = profile.id;
    _statusMessage = null;
    notifyListeners();
    try {
      await domain.flash(dieService, profile);
      _dieHash = _hashes[profile.id];
      _statusMessage = '✓ "${profile.name}" flashed to die';
      return Result.value(null);
    } catch (e) {
      _statusMessage = 'Transfer failed: $e';
      return Result.error(Exception('$e'));
    } finally {
      _transferringId = null;
      notifyListeners();
    }
  }

  Future<Result<void>> _previewAnimation(PixelProfile profile, String transferId, int animIndex) async {
    _transferringId = transferId;
    _statusMessage = null;
    notifyListeners();
    try {
      await domain.preview(dieService, profile, animIndex);
      _statusMessage = 'Preview sent';
      return Result.value(null);
    } catch (e) {
      _statusMessage = 'Preview failed: $e';
      return Result.error(Exception('$e'));
    } finally {
      _transferringId = null;
      notifyListeners();
    }
  }

  Future<Result<void>> _deleteProfile(PixelProfile profile) async {
    try {
      await domain.delete(profile.id);
      await _load();
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  Future<Result<void>> _saveEdited(PixelProfile profile) async {
    try {
      await domain.save(profile);
      await _load();
      return Result.value(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }
}
