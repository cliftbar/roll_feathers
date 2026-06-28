import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/util/command.dart';

/// ViewModel for [PixelsProfileEditorScreen] (MVVM + Command).
///
/// Owns the editable animation/rule lists and the die-bound preview. The name
/// field stays a widget-local controller (ephemeral form state); dialogs return
/// results that the widget hands to the mutation methods here.
class PixelsProfileEditorViewModel extends ChangeNotifier {
  PixelsProfileEditorViewModel(this.domain, this.dieService, PixelProfile initial)
      : _id = initial.id,
        _brightness = initial.brightness,
        initialName = initial.name,
        animations = List.of(initial.animations),
        rules = List.of(initial.rules) {
    preview = Command2(_preview);
  }

  final PixelProfileDomain domain;
  final PixelDieService? dieService;
  final String _id;
  final int _brightness;

  /// The name to seed the (widget-local) name field with.
  final String initialName;

  /// Whether live preview is available (a die is connected).
  bool get canPreview => dieService != null;

  /// The built-in profile catalog (via the domain), for the import picker.
  List<BuiltinProfile> get builtins => domain.builtins();

  /// The active die's type (d20 fallback when no die); built-ins are
  /// die-agnostic in their *animations*, so this only affects rule conditions.
  PixelDieType get dieType => dieService?.dieType ?? PixelDieType.d20;

  final List<PixelAnimation> animations;
  final List<PixelRule> rules;

  late final Command2<void, List<PixelAnimation>, int> preview;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;
  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  // ── Animation mutations ─────────────────────────────────────────────────────

  void addAnimation(PixelAnimation anim) {
    animations.add(anim);
    notifyListeners();
  }

  void replaceAnimation(int index, PixelAnimation anim) {
    animations[index] = anim;
    notifyListeners();
  }

  void deleteAnimation(int index) {
    animations.removeAt(index);
    // Fix any rules that referenced a now-out-of-range animation index.
    final fixed = rules.map((r) {
      final actions = r.actions.map((a) {
        if (a is PixelActionPlayAnimation && a.animIndex >= animations.length) {
          return PixelActionPlayAnimation(animIndex: (animations.length - 1).clamp(0, 255));
        }
        return a;
      }).toList();
      return PixelRule(condition: r.condition, actions: actions);
    }).toList();
    rules
      ..clear()
      ..addAll(fixed);
    notifyListeners();
  }

  /// Imports the chosen built-in animation plus its transitive references,
  /// appending the resolved clones. Returns how many were added (≥1).
  int importAnimation(List<PixelAnimation> source, int index) {
    final imported = domain.importAnimation(source, index, animations.length);
    animations.addAll(imported);
    notifyListeners();
    return imported.length;
  }

  // ── Rule mutations ──────────────────────────────────────────────────────────

  void addRule(PixelRule rule) {
    rules.add(rule);
    notifyListeners();
  }

  void replaceRule(int index, PixelRule rule) {
    rules[index] = rule;
    notifyListeners();
  }

  void deleteRule(int index) {
    rules.removeAt(index);
    notifyListeners();
  }

  // ── Build / preview ─────────────────────────────────────────────────────────

  /// The profile to return from the editor on Save.
  PixelProfile buildProfile(String name) => PixelProfile(
        id: _id,
        name: name.trim().isEmpty ? 'Unnamed' : name.trim(),
        brightness: _brightness,
        animations: List.of(animations),
        rules: List.of(rules),
      );

  /// Previews [anim] (possibly uncommitted) in the context of the current list:
  /// substitutes it at [replaceIndex] when editing, or appends when adding, then
  /// plays that slot — keeping sibling indices valid for Sequences.
  Future<void> previewInContext(PixelAnimation anim, {int? replaceIndex}) {
    final anims = List<PixelAnimation>.of(animations);
    final int playIndex;
    if (replaceIndex != null) {
      anims[replaceIndex] = anim;
      playIndex = replaceIndex;
    } else {
      anims.add(anim);
      playIndex = anims.length - 1;
    }
    return preview.execute(anims, playIndex);
  }

  Future<Result<void>> _preview(List<PixelAnimation> set, int playIndex) async {
    final service = dieService;
    if (service == null) return Result.value(null);
    _statusMessage = null;
    notifyListeners();
    try {
      final profile = PixelProfile(id: '', name: 'preview', animations: set, rules: const []);
      await domain.preview(service, profile, playIndex);
      _statusMessage = 'Preview sent';
      return Result.value(null);
    } catch (e) {
      _statusMessage = 'Preview failed: $e';
      return Result.error(Exception('$e'));
    } finally {
      notifyListeners();
    }
  }
}
