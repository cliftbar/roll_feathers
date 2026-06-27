import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/core/pixels/animation_import.dart';
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

void main() {
  group('resolveAnimationImport', () {
    // A source set: [0] solid, [1] solid, [2] sequence → plays 0 then 1.
    List<PixelAnimation> sourceSet() => [
      PixelAnimationSimple(durationMs: 100, color: const PixelColor(10, 0, 0)),
      PixelAnimationSimple(durationMs: 200, color: const PixelColor(0, 20, 0)),
      PixelAnimationSequence(durationMs: 300, entries: [(0, 50), (1, 60)]),
    ];

    test('a self-contained animation imports as a single clone', () {
      final result = resolveAnimationImport(sourceSet(), 1, 5);
      expect(result, hasLength(1));
      expect((result[0] as PixelAnimationSimple).durationMs, 200);
    });

    test('clones are independent of the source', () {
      final source = sourceSet();
      final result = resolveAnimationImport(source, 0, 0);
      (result[0] as PixelAnimationSimple).durationMs = 999;
      expect((source[0] as PixelAnimationSimple).durationMs, 100); // unchanged
    });

    test('importing a Sequence pulls in referenced animations and remaps indices', () {
      // Destination already holds 4 animations → clones land at 4,5,6.
      final result = resolveAnimationImport(sourceSet(), 2, 4);

      // The Sequence (src idx 2) + its two referenced animations (0 and 1).
      expect(result, hasLength(3));

      // Append order is ascending source index: [0]→dest4, [1]→dest5, [2]→dest6.
      expect(result[0], isA<PixelAnimationSimple>());
      expect(result[1], isA<PixelAnimationSimple>());
      final seq = result[2] as PixelAnimationSequence;

      // Sequence entries remapped from source {0,1} to dest {4,5}; delays intact.
      expect(seq.entries, [(4, 50), (5, 60)]);
    });

    test('nested Sequences resolve transitively', () {
      final source = [
        PixelAnimationSimple(durationMs: 100, color: const PixelColor(1, 0, 0)), // 0
        PixelAnimationSequence(durationMs: 200, entries: [(0, 10)]),             // 1 → 0
        PixelAnimationSequence(durationMs: 300, entries: [(1, 20)]),             // 2 → 1
      ];
      final result = resolveAnimationImport(source, 2, 0);

      // Closure {0,1,2} → dest {0,1,2}.
      expect(result, hasLength(3));
      expect((result[1] as PixelAnimationSequence).entries, [(0, 10)]);
      expect((result[2] as PixelAnimationSequence).entries, [(1, 20)]);
    });
  });
}
