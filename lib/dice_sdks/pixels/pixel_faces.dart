import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';

/// Pixels-protocol face semantics: the canonical mapping between a die's face
/// *values*, their *indices* (bit positions), and condition face *masks*, per
/// die type.
///
/// This is a faithful port of the official `DiceUtils` (which lives in the
/// `pixels-core-animation` SDK package) — intrinsic SDK knowledge any consumer
/// needs to interpret rolls or build profiles. **Current firmware only**: the
/// firmware-timestamp / "bad normals" remaps are intentionally not ported (see
/// docs/architecture.md / the die-type plan), so the math is timestamp-free and
/// d4 is the trivial `face-1`/`index+1` case.
class PixelFaces {
  PixelFaces._();

  /// Number of faces for [dieType].
  static int faceCount(PixelDieType dieType) {
    switch (dieType) {
      case PixelDieType.unknown:
        return 0;
      case PixelDieType.d4:
        return 4;
      case PixelDieType.d6:
      case PixelDieType.d6Pipped:
      case PixelDieType.d6Fudge:
        return 6;
      case PixelDieType.d8:
        return 8;
      case PixelDieType.d10:
      case PixelDieType.d00:
        return 10;
      case PixelDieType.d12:
        return 12;
      case PixelDieType.d20:
        return 20;
    }
  }

  /// The list of face *values* for [dieType] (d10 → 0–9, d00 → 0/10/…/90,
  /// everything else → 1..N).
  static List<int> dieFaces(PixelDieType dieType) {
    switch (dieType) {
      case PixelDieType.unknown:
        return const [];
      case PixelDieType.d4:
        return const [1, 2, 3, 4];
      case PixelDieType.d6:
      case PixelDieType.d6Pipped:
      case PixelDieType.d6Fudge:
        return const [1, 2, 3, 4, 5, 6];
      case PixelDieType.d8:
        return const [1, 2, 3, 4, 5, 6, 7, 8];
      case PixelDieType.d10:
        return const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      case PixelDieType.d00:
        return const [0, 10, 20, 30, 40, 50, 60, 70, 80, 90];
      case PixelDieType.d12:
        return const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      case PixelDieType.d20:
        return const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
    }
  }

  /// The "highest" face value (top face) for [dieType]. d10/d00 → 0.
  static int highestFace(PixelDieType dieType) =>
      (dieType == PixelDieType.d10 || dieType == PixelDieType.d00) ? 0 : faceCount(dieType);

  /// The "lowest" face value for [dieType]. d00 → 10, otherwise 1.
  static int lowestFace(PixelDieType dieType) => dieType == PixelDieType.d00 ? 10 : 1;

  /// Bit index for a face *value* (current firmware): d10 → value, d00 →
  /// value/10, everything else → value-1.
  static int indexFromFace(int face, PixelDieType dieType) {
    switch (dieType) {
      case PixelDieType.d10:
      case PixelDieType.unknown:
        return face;
      case PixelDieType.d00:
        return face ~/ 10;
      default:
        return face - 1;
    }
  }

  /// Face *value* for a bit/face index (current firmware): inverse of
  /// [indexFromFace]. d10 → index, d00 → index*10, everything else → index+1.
  static int faceFromIndex(int index, PixelDieType dieType) {
    switch (dieType) {
      case PixelDieType.d10:
      case PixelDieType.unknown:
        return index;
      case PixelDieType.d00:
        return index * 10;
      default:
        return index + 1;
    }
  }

  /// A condition face mask (32-bit) for the given face *values*.
  static int faceMask(Iterable<int> faces, PixelDieType dieType) =>
      faces.fold(0, (mask, f) => mask | (1 << indexFromFace(f, dieType)));
}
