import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart' as pix;
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/testing/pixels_die_simulator.dart';

PixelProfile _testProfile({
  String id = 'test',
  int durationMs = 500,
  PixelColor color = const PixelColor(255, 0, 0),
}) => PixelProfile(
  id: id,
  name: 'Test Profile',
  brightness: 200,
  animations: [
    PixelAnimationSimple(durationMs: durationMs, color: color, count: 1, fade: 0),
  ],
  rules: [
    PixelRule(
      condition: PixelConditionRolled(),
      actions: [PixelActionPlayAnimation(animIndex: 0)],
    ),
  ],
);

// Minimal blink message for testing the simulator's blink handling.
class _BlinkMsg extends TxMessage {
  _BlinkMsg() : super(id: 29); // blink = 29

  @override
  List<int> toBuffer() => [29, 1, 244, 1, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1];
}

// setName message for direct simulator testing.
class _SetNameMsg extends TxMessage {
  final String name;
  _SetNameMsg(this.name) : super(id: 51);

  @override
  List<int> toBuffer() {
    final encoded = name.codeUnits.take(31).toList();
    final buf = List<int>.filled(33, 0);
    buf[0] = 51;
    for (var i = 0; i < encoded.length; i++) buf[1 + i] = encoded[i];
    return buf;
  }
}

void main() {
  group('PixelsDieSimulator low-level', () {
    late PixelsDieSimulator sim;

    setUp(() => sim = PixelsDieSimulator(name: 'TestDie'));
    tearDown(() => sim.dispose());

    test('responds to blink with blinkAck', () async {
      await sim.sendAndWaitFor<pix.MessageNone>(
        _BlinkMsg(),
        pix.PixelMessageType.blinkAck,
        timeout: const Duration(seconds: 1),
      );
      // sendAndWaitFor returned → ack received
    });

    test('responds to setName with setNameAck and updates name', () async {
      await sim.sendAndWaitFor<pix.MessageNone>(
        _SetNameMsg('NewName'),
        pix.PixelMessageType.setNameAck,
        timeout: const Duration(seconds: 1),
      );
      expect(sim.name, 'NewName');
    });

    test('responds to whoAreYou with iAmADie', () async {
      final msg = await sim.sendAndWaitFor<pix.MessageIAmADie>(
        pix.MessageWhoAreYou(),
        pix.PixelMessageType.iAmADie,
        timeout: const Duration(seconds: 1),
      );
      expect(msg.ledCount, 20);
    });
  });

  group('PixelDieService', () {
    late PixelsDieSimulator sim;
    late PixelDieService transfer;

    setUp(() {
      sim = PixelsDieSimulator();
      transfer = PixelDieService(sim);
    });

    tearDown(() => sim.dispose());

    test('transferProfile completes successfully', () async {
      await expectLater(transfer.transferProfile(_testProfile()), completes);
    });

    test('transferProfile stores data in simulator flash', () async {
      await transfer.transferProfile(_testProfile());
      expect(sim.flashProfileBytes, isNotNull);
      expect(sim.flashProfileBytes!.isNotEmpty, isTrue);
    });

    test('transferProfile data matches toByteArray output', () async {
      final profile = _testProfile();
      await transfer.transferProfile(profile);
      final expected = PixelDataSet(profile).toByteArray();
      expect(sim.flashProfileBytes, equals(expected));
    });

    test('transferInstantAnimation completes successfully', () async {
      await expectLater(transfer.transferInstantAnimation(_testProfile()), completes);
    });

    test('transferInstantAnimation stores data in simulator RAM', () async {
      await transfer.transferInstantAnimation(_testProfile());
      expect(sim.instantAnimationBytes, isNotNull);
      expect(sim.instantAnimationBytes!.isNotEmpty, isTrue);
    });

    test('instant animation data matches toAnimationsByteArray output', () async {
      final profile = _testProfile();
      await transfer.transferInstantAnimation(profile);
      final expected = PixelDataSet(profile).toAnimationsByteArray();
      expect(sim.instantAnimationBytes, equals(expected));
    });

    test('setName renames the simulated die', () async {
      await transfer.setName('Renamed Die');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(sim.name, 'Renamed Die');
    });

    test('playInstantAnimation sends without error', () async {
      await expectLater(
        transfer.playInstantAnimation(animIndex: 0, faceIndex: 5, loopCount: 2),
        completes,
      );
    });

    test('whoAreYou after transferProfile returns updated hash', () async {
      final profile = _testProfile();
      await transfer.transferProfile(profile);

      final expectedHash = PixelDataSet(profile).computeHash().toUnsigned(32);

      final response = await sim.sendAndWaitFor<pix.MessageIAmADie>(
        pix.MessageWhoAreYou(),
        pix.PixelMessageType.iAmADie,
        timeout: const Duration(seconds: 1),
      );
      expect(response.dataSetHash.toUnsigned(32), expectedHash);
    });

    test('rainbow animation profile transfers successfully', () async {
      final profile = PixelProfile(
        id: 'rainbow',
        name: 'Rainbow',
        animations: [PixelAnimationRainbow(durationMs: 2000, intensity: 200)],
        rules: [
          PixelRule(
            condition: PixelConditionRolling(repeatPeriodMs: 500),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
        ],
      );
      await expectLater(transfer.transferProfile(profile), completes);
    });

    test('helloGoodbye condition profile transfers successfully', () async {
      final profile = PixelProfile(
        id: 'hello',
        name: 'Hello',
        animations: [PixelAnimationSimple(durationMs: 1000)],
        rules: [
          PixelRule(
            condition: PixelConditionHelloGoodbye(flags: 1),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
        ],
      );
      await expectLater(transfer.transferProfile(profile), completes);
    });

    test('large profile (5 animations, 5 rules) transfers without error', () async {
      final profile = PixelProfile(
        id: 'large',
        name: 'Large',
        animations: List.generate(5, (i) => PixelAnimationSimple(
          durationMs: 200 + i * 100,
          color: PixelColor(i * 50, 255 - i * 40, i * 30),
        )),
        rules: List.generate(5, (i) => PixelRule(
          condition: PixelConditionRolled(faceMask: 1 << i),
          actions: [PixelActionPlayAnimation(animIndex: i)],
        )),
      );
      await expectLater(transfer.transferProfile(profile), completes);
    });

    test('profile larger than one chunk (>100 bytes) transfers in multiple chunks', () async {
      // This profile has 5 animations each with 12 bytes + other overhead, > 100 bytes total
      final profile = PixelProfile(
        id: 'bigchunk',
        name: 'BigChunk',
        animations: List.generate(10, (i) => PixelAnimationSimple(
          durationMs: 100 + i,
          color: PixelColor(i * 25, 0, 0),
        )),
        rules: List.generate(10, (i) => PixelRule(
          condition: PixelConditionRolled(faceMask: 1 << (i % 20)),
          actions: [PixelActionPlayAnimation(animIndex: i)],
        )),
      );
      final bytes = PixelDataSet(profile).toByteArray();
      expect(bytes.length, greaterThan(100)); // ensure multi-chunk
      await expectLater(transfer.transferProfile(profile), completes);
      expect(sim.flashProfileBytes, equals(bytes));
    });
  });

  group('PixelsDieSimulator roll simulation', () {
    test('simulateRoll emits rolling then rolled states with correct face', () async {
      final sim = PixelsDieSimulator();
      addTearDown(sim.dispose);

      final states = <(int, int)>[]; // (state, face)
      sim.notifyStream.listen((data) {
        if (data.isNotEmpty && data[0] == pix.PixelMessageType.rollState.index) {
          states.add((data[1], data[2]));
        }
      });

      sim.simulateRoll(faceIndex: 15);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(states.any((s) => s.$1 == 3), isTrue); // rolling
      expect(states.any((s) => s.$1 == 1 && s.$2 == 15), isTrue); // rolled on face 15
      expect(sim.currentFace, 15);
    });

    test('simulateHandling emits handling state', () async {
      final sim = PixelsDieSimulator();
      addTearDown(sim.dispose);

      final states = <int>[];
      sim.notifyStream.listen((data) {
        if (data.isNotEmpty && data[0] == pix.PixelMessageType.rollState.index) {
          states.add(data[1]);
        }
      });

      sim.simulateHandling();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.contains(2), isTrue); // handling
    });

    test('simulateBattery emits batteryLevel packet and is receivable via waitFor', () async {
      final sim = PixelsDieSimulator();
      addTearDown(sim.dispose);

      final future = sim.waitFor<pix.MessageBatteryLevel>(
        pix.PixelMessageType.batteryLevel,
        timeout: const Duration(seconds: 1),
      );
      sim.simulateBattery(42, batteryState: 1); // 1 = low
      final msg = await future;
      expect(msg.batteryLevel, 42);
      expect(msg.batteryState, 1);
    });

    test('simulateNotifyUser emits notifyUser and is receivable via waitFor', () async {
      final sim = PixelsDieSimulator();
      addTearDown(sim.dispose);

      final future = sim.waitFor<pix.MessageNotifyUser>(
        pix.PixelMessageType.notifyUser,
        timeout: const Duration(seconds: 1),
      );
      sim.simulateNotifyUser(timeoutSec: 5, ok: true, cancel: false, message: 'Update?');
      final msg = await future;
      expect(msg.timeoutSec, 5);
      expect(msg.ok, isTrue);
      expect(msg.cancel, isFalse);
      expect(msg.message, 'Update?');
    });

    test('iAmADie after transferProfile reflects updated hash', () async {
      final sim = PixelsDieSimulator();
      addTearDown(sim.dispose);
      final transfer = PixelDieService(sim);
      final profile = _testProfile();

      await transfer.transferProfile(profile);
      final expectedHash = PixelDataSet(profile).computeHash().toUnsigned(32);

      final response = await sim.sendAndWaitFor<pix.MessageIAmADie>(
        pix.MessageWhoAreYou(),
        pix.PixelMessageType.iAmADie,
        timeout: const Duration(seconds: 1),
      );
      expect(response.dataSetHash.toUnsigned(32), expectedHash);
    });

    test('simulateBattery is reflected in iAmADie after update', () async {
      final sim = PixelsDieSimulator();
      addTearDown(sim.dispose);

      sim.simulateBattery(33);

      final response = await sim.sendAndWaitFor<pix.MessageIAmADie>(
        pix.MessageWhoAreYou(),
        pix.PixelMessageType.iAmADie,
        timeout: const Duration(seconds: 1),
      );
      expect(response.batteryLevel, 33);
    });
  });
}
