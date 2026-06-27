// Verifies our built-in Pixels profiles serialize byte-for-byte identically to
// the official Pixels app, by asserting the DataSet hash matches the value the
// official pixels-js SDK computes for the same profile on a d20.
//
// Ground-truth hashes were generated from the official SDK
// (packages/pixels-edit-animation createLibraryProfile(name, "d20") →
// createDataSetForProfile().toDataSet() → DataSet.computeHash()), and the
// Worm value (0x8A5AC4BD) was additionally confirmed against a live die that
// had the official Worm flashed.
//
// Run:  flutter test test/pixels_official_hash_parity_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_patterns.dart';

// Official pixels-js d20 hashes, keyed by our built-in profile name.
const Map<String, int> _officialD20Hashes = {
  'Default Profile': 0xC60D3C5B,
  'Empty': 0xB2DA7236,
  'Speak Numbers': 0xE3537BCD,
  'Waterfall': 0x3DA9E5EF,
  'Fountain': 0xAA2C0888,
  'Spinning': 0x6B70FCE2,
  'Spiral': 0xBDEAB328,
  'Noise': 0x0D0818B4,
  'Flashy': 0xD4314D97,
  'High Low': 0x6AD1B481,
  'Worm': 0x8A5AC4BD,
  'Rose': 0x884F0C81,
  'Fire': 0xABC76630,
  'Magic': 0x58CC944B,
  'Water': 0x48D283A0,
};

String _hex(int h) => '0x${h.toUnsigned(32).toRadixString(16).toUpperCase().padLeft(8, '0')}';

void main() {
  setUp(() => registerBuiltinPatterns(kBuiltinPatterns));

  group('official hash parity (d20)', () {
    for (final entry in _officialD20Hashes.entries) {
      test('${entry.key} matches official', () {
        final preset = kBuiltinProfiles.firstWhere((p) => p.name == entry.key);
        final ourHash = PixelDataSet(preset.build()).computeHash().toUnsigned(32);
        expect(
          ourHash,
          entry.value,
          reason: '${entry.key}: ours=${_hex(ourHash)} official=${_hex(entry.value)}',
        );
      });
    }
  });
}
