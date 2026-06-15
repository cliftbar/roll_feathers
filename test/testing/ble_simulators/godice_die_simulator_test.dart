import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart' as godice;
import 'package:roll_feathers/testing/ble_simulators/godice_die_simulator.dart';

void main() {
  late GoDiceDieSimulator sim;
  late GoDiceBle die;

  setUp(() async {
    sim = GoDiceDieSimulator(dieType: godice.GodiceDieType.d6);
    die = await GoDiceBle.create(
        dieFaceType: godice.GodiceDieType.d6, device: sim);
  });

  tearDown(() => sim.dispose());

  test('rollTo fires callback and lands on correct face', () async {
    bool callbackFired = false;
    die.addRollCallback(DiceRollState.rolled, 'test', (_) => callbackFired = true);

    sim.rollTo(4);

    await Future.delayed(Duration(milliseconds: 10));
    expect(die.state.currentFaceValue, 4);
    expect(die.state.rollState, DiceRollState.rolled.index);
    expect(callbackFired, isTrue);
  });

  test('rollTo works for all valid d6 faces', () async {
    for (int face = 1; face <= 6; face++) {
      sim.rollTo(face);
      await Future.delayed(Duration(milliseconds: 10));
      expect(die.state.currentFaceValue, face,
          reason: 'face $face did not land correctly');
    }
  });

  test('setRolling puts die in rolling state', () async {
    sim.setRolling();
    await Future.delayed(Duration(milliseconds: 10));
    expect(die.state.rollState, DiceRollState.rolling.index);
  });

  test('setBattery updates battery level', () async {
    sim.setBattery(55);
    await Future.delayed(Duration(milliseconds: 10));
    expect(die.state.batteryLevel, 55);
  });

  test('rollTo throws for invalid face value', () {
    expect(() => sim.rollTo(7), throwsArgumentError);
    expect(() => sim.rollTo(0), throwsArgumentError);
  });

  test('app init messages are captured', () async {
    // GoDiceBle.create sends 2 init messages
    expect(sim.writtenMessages.length, greaterThanOrEqualTo(2));
  });

  test('d20 simulator rolls all faces correctly', () async {
    final d20sim = GoDiceDieSimulator(dieType: godice.GodiceDieType.d20);
    final d20 = await GoDiceBle.create(
        dieFaceType: godice.GodiceDieType.d20, device: d20sim);

    for (int face = 1; face <= 20; face++) {
      d20sim.rollTo(face);
      await Future.delayed(Duration(milliseconds: 10));
      expect(d20.state.currentFaceValue, face,
          reason: 'd20 face $face did not land correctly');
    }
    d20sim.dispose();
  });
}
