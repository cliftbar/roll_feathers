// Verifies our built-in Pixels profiles serialize byte-for-byte identically to
// the official Pixels app, for *every* die type — by asserting the DataSet hash
// matches the value the official pixels-js SDK computes for the same profile on
// each die type.
//
// Ground-truth hashes were generated from the official SDK
// (packages/pixels-edit-animation createLibraryProfile(name, dieType) →
// createDataSetForProfile().toDataSet() → DataSet.computeHash()) over
// {d4, d6, d8, d10, d00, d12, d20}. The d20 Worm value (0x8A5AC4BD) was
// additionally confirmed against a live die with the official Worm flashed.
//
// Note: d10 and d00 share all face indices, so their hashes are identical for
// every profile EXCEPT "Speak Numbers" — which speaks the raw face value
// (0–9 vs 0/10/…/90), producing different text/condition bytes.
//
// Run:  flutter test test/pixels_official_hash_parity_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';

// Official pixels-js hashes, keyed by die type then by our built-in profile name.
const Map<PixelDieType, Map<String, int>> _officialHashes = {
  PixelDieType.d4: {
    'Default Profile': 0x9384B87B,
    'Empty': 0xDAE62036,
    'Speak Numbers': 0x11218D0D,
    'Waterfall': 0x40CAA18F,
    'Fountain': 0xC9F95BA8,
    'Spinning': 0xB7886B02,
    'Spiral': 0x966BEB48,
    'Noise': 0x3BCEFBD4,
    'Flashy': 0x1CC873B7,
    'High Low': 0xF964CFE1,
    'Worm': 0x7A95DDEB,
    'Rose': 0xC2E2A771,
    'Fire': 0xC63D3FD0,
    'Magic': 0xC7D27C6B,
    'Water': 0x0C0B5810,
  },
  PixelDieType.d6: {
    'Default Profile': 0x8C9C46A3,
    'Empty': 0x4F1DC71E,
    'Speak Numbers': 0x59DAEE30,
    'Waterfall': 0xBAF4C717,
    'Fountain': 0xB77E4270,
    'Spinning': 0x7F09D81A,
    'Spiral': 0x8445F250,
    'Noise': 0xCBE9C24C,
    'Flashy': 0xBB120AAF,
    'High Low': 0x4FED3C79,
    'Worm': 0xBC471085,
    'Rose': 0xCB07866F,
    'Fire': 0xB20FE688,
    'Magic': 0x139725B3,
    'Water': 0x29EC714E,
  },
  PixelDieType.d8: {
    'Default Profile': 0xCA7BB5C3,
    'Empty': 0x0094D4BE,
    'Speak Numbers': 0xB6A65D95,
    'Waterfall': 0x9910DB77,
    'Fountain': 0xCAD2AE10,
    'Spinning': 0x0850F03A,
    'Spiral': 0x603FB5F0,
    'Noise': 0xBE01C4EC,
    'Flashy': 0xB702840F,
    'High Low': 0x17C18199,
    'Worm': 0x2A4E9865,
    'Rose': 0x29973CCD,
    'Fire': 0xDA975028,
    'Magic': 0x8EDFCFD3,
    'Water': 0xE0EEED6C,
  },
  PixelDieType.d10: {
    'Default Profile': 0x20C77F21,
    'Empty': 0x45FC6C9F,
    'Speak Numbers': 0x78DF1B63,
    'Waterfall': 0x351D6D55,
    'Fountain': 0x7299DDB2,
    'Spinning': 0xB80A2B98,
    'Spiral': 0x6E2BE992,
    'Noise': 0xBF081F8E,
    'Flashy': 0x0CA0E9AD,
    'High Low': 0xBDA03CBB,
    'Worm': 0x48870826,
    'Rose': 0xD3CDAFC8,
    'Fire': 0x5000A28A,
    'Magic': 0xE1F02C31,
    'Water': 0x22388DA9,
  },
  PixelDieType.d00: {
    'Default Profile': 0x20C77F21,
    'Empty': 0x45FC6C9F,
    'Speak Numbers': 0x459FAEBF,
    'Waterfall': 0x351D6D55,
    'Fountain': 0x7299DDB2,
    'Spinning': 0xB80A2B98,
    'Spiral': 0x6E2BE992,
    'Noise': 0xBF081F8E,
    'Flashy': 0x0CA0E9AD,
    'High Low': 0xBDA03CBB,
    'Worm': 0x48870826,
    'Rose': 0xD3CDAFC8,
    'Fire': 0x5000A28A,
    'Magic': 0xE1F02C31,
    'Water': 0x22388DA9,
  },
  PixelDieType.d12: {
    'Default Profile': 0x58E03384,
    'Empty': 0x5A2F6936,
    'Speak Numbers': 0x2ED247AD,
    'Waterfall': 0x2C2D16F0,
    'Fountain': 0x41B34D97,
    'Spinning': 0x4B0083BD,
    'Spiral': 0xFEECEB77,
    'Noise': 0x77E10C6B,
    'Flashy': 0x214D3A08,
    'High Low': 0x4F8345DE,
    'Worm': 0xCB2FA062,
    'Rose': 0x2806FE06,
    'Fire': 0x9F2F67AF,
    'Magic': 0x8E34F654,
    'Water': 0x2B358727,
  },
  PixelDieType.d20: {
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
  },
};

String _hex(int h) => '0x${h.toUnsigned(32).toRadixString(16).toUpperCase().padLeft(8, '0')}';

void main() {
  for (final dieEntry in _officialHashes.entries) {
    final dieType = dieEntry.key;
    group('official hash parity (${dieType.name})', () {
      for (final entry in dieEntry.value.entries) {
        test('${entry.key} matches official', () {
          final preset = kBuiltinProfiles.firstWhere((p) => p.name == entry.key);
          final ourHash = PixelDataSet(preset.build(dieType)).computeHash().toUnsigned(32);
          expect(
            ourHash,
            entry.value,
            reason: '${entry.key} (${dieType.name}): '
                'ours=${_hex(ourHash)} official=${_hex(entry.value)}',
          );
        });
      }
    });
  }
}
