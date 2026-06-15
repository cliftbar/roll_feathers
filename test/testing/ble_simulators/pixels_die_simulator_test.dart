import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/testing/ble_simulators/pixels_die_simulator.dart';

void main() {
  late PixelsDieSimulator sim;
  late PixelDie die;

  setUp(() async {
    sim = PixelsDieSimulator(dieType: pix.PixelDieType.d20);
    die = await PixelDie.create(device: sim);
  });

  tearDown(() => sim.dispose());

  test('identify sets die type and initial face', () {
    sim.identify(faceValue: 5, battery: 80);
    expect(die.info?.pixelDieTypeFaces, pix.PixelDieType.d20);
    expect(die.state.currentFaceValue, 5);
    expect(die.state.batteryLevel, 80);
  });

  test('rollTo emits rolling then rolled and fires callback', () async {
    bool callbackFired = false;
    die.addRollCallback(DiceRollState.rolled, 'test', (_) => callbackFired = true);

    sim.rollTo(17);

    await Future.delayed(Duration(milliseconds: 10));
    expect(die.state.currentFaceValue, 17);
    expect(die.state.rollState, DiceRollState.rolled.index);
    expect(callbackFired, isTrue);
  });

  test('setRolling emits rolling state', () async {
    sim.setRolling();
    await Future.delayed(Duration(milliseconds: 10));
    expect(die.state.rollState, DiceRollState.rolling.index);
  });

  test('setBattery updates battery level', () async {
    sim.setBattery(42);
    await Future.delayed(Duration(milliseconds: 10));
    expect(die.state.batteryLevel, 42);
  });

  test('app write messages are captured for assertion', () async {
    // PixelDie.create sends WhoAreYou on init
    expect(sim.writtenMessages, isNotEmpty);
    expect(sim.writtenMessages.first.first,
        pix.PixelMessageType.whoAreYou.index);
  });
}
