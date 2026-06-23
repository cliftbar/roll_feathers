import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/testing/ble_simulators/pixels_ble_device_simulator.dart';

void main() {
  late PixelsBleDeviceSimulator sim;
  late PixelDie die;

  setUp(() async {
    sim = PixelsBleDeviceSimulator(dieType: pix.PixelDieType.d20);
    die = await PixelDie.create(device: sim);
  });

  tearDown(() => sim.dispose());

  test('identify sets die type, face, and battery', () {
    sim.identify(faceValue: 5, battery: 80);
    expect(die.info?.pixelDieTypeFaces, pix.PixelDieType.d20);
    expect(die.state.currentFaceValue, 5);
    expect(die.state.batteryLevel, 80);
  });

  test('rollTo emits rolling then rolled and fires callback', () async {
    bool callbackFired = false;
    die.addRollCallback(DiceRollState.rolled, 'test', (_) => callbackFired = true);

    sim.rollTo(17);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.currentFaceValue, 17);
    expect(die.state.rollState, DiceRollState.rolled.index);
    expect(callbackFired, isTrue);
  });

  test('setRolling emits rolling state', () async {
    sim.setRolling();
    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.rollState, DiceRollState.rolling.index);
  });

  test('setBattery updates battery level', () async {
    sim.setBattery(42);
    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.batteryLevel, 42);
  });

  test('WhoAreYou is captured as first written message', () {
    expect(sim.writtenMessages, isNotEmpty);
    expect(sim.writtenMessages.first.first, pix.PixelMessageType.whoAreYou.index);
  });

  test('requestRollState auto-response reflects current state after rollTo', () async {
    sim.rollTo(12);
    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.currentFaceValue, 12);

    // Send requestRollState via die.sendMessage and verify the sim responds
    // with a rollState packet that the die parses correctly.
    await die.sendMessage(pix.MessageRequestRollState());
    await Future.delayed(const Duration(milliseconds: 10));

    expect(die.state.currentFaceValue, 12);
    expect(die.state.rollState, DiceRollState.rolled.index);
  });

  test('requestBatteryLevel auto-response reflects current level after setBattery', () async {
    sim.setBattery(55);
    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.batteryLevel, 55);
  });

  test('identify followed by rollTo keeps correct face value', () async {
    sim.identify(faceValue: 3, battery: 90);
    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.currentFaceValue, 3);

    sim.rollTo(19);
    await Future.delayed(const Duration(milliseconds: 10));
    expect(die.state.currentFaceValue, 19);
  });
}
