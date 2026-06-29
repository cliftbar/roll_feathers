/// Pure animation-import logic, decoupled from UI and I/O.
///
/// This is core (domain) logic: a side-effect-free transform over animation
/// models, called by [PixelProfileDomain]. It lives under `core/` per the
/// architecture (pure logic + models). It currently imports the animation
/// models from `dice_sdks/` because those model types have not yet been
/// relocated to `core/` — see the "models → core" item in
/// `docs/architecture.md`. The dependency is on the model classes only (not on
/// the SDK's transport/protocol code), so it is conceptually core→core.
library;

import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';

/// Resolves an animation "import": clones [source]'s animation at [index] plus
/// every animation it references (transitively, via [PixelAnimationSequence]
/// entries), remapping Sequence indices to the positions the clones will occupy
/// once appended to a destination list that already holds [destLen] animations.
///
/// Animations can reference siblings by index, so importing one in isolation
/// would leave those references dangling (pointing at unrelated animations in
/// the destination, or out of range). The returned list — in append order — is
/// self-contained: appending it to the destination keeps every reference valid.
///
/// All returned animations are deep clones (JSON round-trip), so mutating them
/// never affects [source].
List<PixelAnimation> resolveAnimationImport(List<PixelAnimation> source, int index, int destLen) {
  // Transitive closure of sibling references, starting from the chosen index.
  final closure = <int>{};
  void visit(int i) {
    if (i < 0 || i >= source.length || !closure.add(i)) return;
    final a = source[i];
    if (a is PixelAnimationSequence) {
      for (final e in a.entries) {
        visit(e.$1);
      }
    }
  }

  visit(index);

  // Deterministic append order (ascending source index) + source→dest remap.
  final ordered = closure.toList()..sort();
  final remap = {for (var k = 0; k < ordered.length; k++) ordered[k]: destLen + k};

  return [
    for (final si in ordered) _cloneAnimationRemapped(source[si], remap),
  ];
}

/// Deep-clones [anim]; if it is a [PixelAnimationSequence], rewrites its entry
/// indices through [remap] (any index absent from [remap] is left untouched).
PixelAnimation _cloneAnimationRemapped(PixelAnimation anim, Map<int, int> remap) {
  final clone = PixelAnimation.fromJson(anim.toJson());
  if (clone is PixelAnimationSequence) {
    final remapped = clone.entries.map((e) => (remap[e.$1] ?? e.$1, e.$2)).toList();
    clone.entries
      ..clear()
      ..addAll(remapped);
  }
  return clone;
}
