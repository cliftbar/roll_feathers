import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';

import '../test_util.dart';

void main() {
  setupLogger(Level.WARNING);

  late RecordingDieDomain dieDomain;
  late RollDomain rollDomain;
  late TestBleDie die;

  setUp(() async {
    dieDomain = RecordingDieDomain();
    final appService = InMemoryAppService();
    final rp = RuleEvaluator(dieDomain, appService, WebhookDomain(appService: appService));
    await rp.init();
    rollDomain = await RollDomain.create(dieDomain, appService, ruleParser: rp);
    die = TestBleDie('die-A');
    // Emit the die so rollStreamListener registers callbacks on it.
    dieDomain.emitDice({'die-A': die});
    // Allow the stream listener to process.
    await Future.delayed(Duration.zero);
  });

  tearDown(() {
    dieDomain.rollingBlinked.clear();
    dieDomain.animationsStopped.clear();
  });

  test('rolling state fires blinkRolling for that die', () async {
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);

    expect(dieDomain.rollingBlinked, contains('die-A'));
  });

  test('rolled state stops animations when rolling flash is enabled', () async {
    die.rollingFlashEnabled = true;
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);
    die.fireRollState(DiceRollState.rolled);
    await Future.delayed(Duration.zero);

    expect(dieDomain.animationsStopped, contains('die-A'));
  });

  test('crooked state stops animations when rolling flash is enabled', () async {
    die.rollingFlashEnabled = true;
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);
    die.fireRollState(DiceRollState.crooked);
    await Future.delayed(Duration.zero);

    expect(dieDomain.animationsStopped, contains('die-A'));
  });

  // Regression guard: when rolling flash is OFF, the app must NOT send
  // StopAllAnimations on landing — doing so clobbered the die's own on-die
  // profile "rolled" animation.
  test('rolled state does NOT stop animations when rolling flash is disabled', () async {
    die.rollingFlashEnabled = false;
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);
    die.fireRollState(DiceRollState.rolled);
    await Future.delayed(Duration.zero);

    expect(dieDomain.animationsStopped, isNot(contains('die-A')));
  });

  test('crooked state does NOT stop animations when rolling flash is disabled', () async {
    die.rollingFlashEnabled = false;
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);
    die.fireRollState(DiceRollState.crooked);
    await Future.delayed(Duration.zero);

    expect(dieDomain.animationsStopped, isNot(contains('die-A')));
  });

  test('crooked state does not process a roll result', () async {
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);
    die.fireRollState(DiceRollState.crooked);
    await Future.delayed(Duration.zero);

    expect(rollDomain.rollHistory, isEmpty);
  });

  test('multiple dice each fire blinkRolling independently', () async {
    final dieB = TestBleDie('die-B');
    dieDomain.emitDice({'die-A': die, 'die-B': dieB});
    await Future.delayed(Duration.zero);

    die.fireRollState(DiceRollState.rolling);
    dieB.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);

    expect(dieDomain.rollingBlinked, containsAll(['die-A', 'die-B']));
  });

  test('repeated rolling state only fires blinkRolling once per session', () async {
    die.fireRollState(DiceRollState.rolling);
    die.fireRollState(DiceRollState.rolling);
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);

    expect(dieDomain.rollingBlinked.where((id) => id == 'die-A').length, equals(1));
  });

  test('blinkRolling fires again on next roll after die settles', () async {
    // First roll
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);
    die.fireRollState(DiceRollState.rolled);
    await Future.delayed(Duration.zero);

    // Second roll — dieBlinking flag should have been reset by rolled callback
    die.fireRollState(DiceRollState.rolling);
    await Future.delayed(Duration.zero);

    expect(dieDomain.rollingBlinked.where((id) => id == 'die-A').length, equals(2));
  });
}
