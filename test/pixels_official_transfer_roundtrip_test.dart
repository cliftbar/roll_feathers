// Transfer-path analog of pixels_official_hash_parity_test.
//
// The parity test checks `build(dieType).computeHash()` in isolation (pure
// serialization). This drives the *full flash path* — PixelDieService →
// PixelsDieSimulator: chunked bulk upload, acks, and reassembly — for every
// built-in profile built for every die type, then asserts the simulator's
// round-tripped DataSet (bytes + hash) matches what we serialized.
//
// Chained with the parity test (which proves our hash equals the official app's),
// this proves each profile flashes to a die of any type and lands with the hash
// the official app expects — the bytes survive the protocol intact.
//
// Run:  flutter test test/pixels_official_transfer_roundtrip_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixel_faces.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';

const List<PixelDieType> _dieTypes = [
  PixelDieType.d4,
  PixelDieType.d6,
  PixelDieType.d8,
  PixelDieType.d10,
  PixelDieType.d00,
  PixelDieType.d12,
  PixelDieType.d20,
];

void main() {
  group('built-in profile flash round-trip (simulator)', () {
    for (final dieType in _dieTypes) {
      group(dieType.name, () {
        for (final preset in kBuiltinProfiles) {
          test('${preset.name} flashes with intact bytes + hash', () async {
            final sim = PixelsDieSimulator(
              dieType: dieType,
              ledCount: PixelFaces.faceCount(dieType),
            );
            addTearDown(sim.dispose);
            final transfer = PixelDieService(sim);

            final profile = preset.build(dieType);
            final ds = PixelDataSet(profile);
            final expectedBytes = ds.toByteArray();
            final expectedHash = ds.computeHash().toUnsigned(32);

            await transfer.transferProfile(profile);

            // Bytes the simulator reassembled from the chunked upload.
            expect(
              sim.flashProfileBytes,
              equals(expectedBytes),
              reason: '${preset.name}/${dieType.name}: flashed bytes differ from serialized output',
            );
            // Hash the simulator computed from those received bytes — what the
            // die would report in IAmADie, and what the UI matches against.
            expect(
              sim.currentDataSetHash?.toUnsigned(32),
              equals(expectedHash),
              reason: '${preset.name}/${dieType.name}: round-tripped hash != computed hash',
            );
          });
        }
      });
    }
  });
}
