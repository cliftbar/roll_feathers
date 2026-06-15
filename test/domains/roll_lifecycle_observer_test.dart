/// Tests that RollDomain calls RollLifecycleObserver hooks at the correct
/// lifecycle points and that observer errors do not crash rolls.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/domains/roll_lifecycle_observer.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';

import '../helpers/dddice_helpers.dart';
import '../test_util.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

Future<({RecordingDieDomain dieDomain, RollDomain rollDomain, TestBleDie die})>
    _setup({List<RollLifecycleObserver> observers = const []}) async {
  final dieDomain = RecordingDieDomain();
  final appService = InMemoryAppService();
  final rp = RuleEvaluator(dieDomain, appService, WebhookDomain(appService: appService));
  await rp.init();
  final rollDomain = await RollDomain.create(
    dieDomain,
    appService,
    ruleParser: rp,
    observers: observers,
  );
  final die = TestBleDie('die-A');
  dieDomain.emitDice({'die-A': die});
  await Future.delayed(Duration.zero);
  return (dieDomain: dieDomain, rollDomain: rollDomain, die: die);
}

/// Triggers a full roll cycle (rolling → rolled) and waits for async effects.
Future<void> _doRoll(TestBleDie die) async {
  die.fireRollState(DiceRollState.rolling);
  await Future.delayed(Duration.zero);
  die.fireRollState(DiceRollState.rolled);
  await Future.delayed(const Duration(milliseconds: 100));
}

void main() {
  setupLogger(Level.WARNING);

  // ─── onDieRolling ─────────────────────────────────────────────────────────

  group('onDieRolling', () {
    test('called once when die enters rolling state', () async {
      final obs = RecordingObserver();
      final env = await _setup(observers: [obs]);
      env.die.fireRollState(DiceRollState.rolling);
      await Future.delayed(Duration.zero);

      expect(obs.rollingDice, hasLength(1));
      expect(obs.rollingDice.first.dieId, equals('die-A'));
    });

    test('NOT called again when rolling fires multiple times in same session', () async {
      final obs = RecordingObserver();
      final env = await _setup(observers: [obs]);
      env.die.fireRollState(DiceRollState.rolling);
      env.die.fireRollState(DiceRollState.rolling);
      env.die.fireRollState(DiceRollState.rolling);
      await Future.delayed(Duration.zero);

      expect(obs.rollingDice, hasLength(1),
          reason: 'dieBlinking guard should suppress duplicate onDieRolling calls');
    });

    test('called again on the next roll after die settled (dieBlinking resets)', () async {
      final obs = RecordingObserver();
      final env = await _setup(observers: [obs]);

      // First roll
      await _doRoll(env.die);
      // Second roll
      env.die.fireRollState(DiceRollState.rolling);
      await Future.delayed(Duration.zero);

      expect(obs.rollingDice.where((d) => d.dieId == 'die-A').length, equals(2));
    });

    test('each of multiple dice triggers onDieRolling independently', () async {
      final obs = RecordingObserver();
      final dieDomain = RecordingDieDomain();
      final app = InMemoryAppService();
      final rp = RuleEvaluator(dieDomain, app, WebhookDomain(appService: app));
      await rp.init();
      await RollDomain.create(dieDomain, app, ruleParser: rp, observers: [obs]);

      final dieA = TestBleDie('die-A');
      final dieB = TestBleDie('die-B');
      dieDomain.emitDice({'die-A': dieA, 'die-B': dieB});
      await Future.delayed(Duration.zero);

      dieA.fireRollState(DiceRollState.rolling);
      dieB.fireRollState(DiceRollState.rolling);
      await Future.delayed(Duration.zero);

      final ids = obs.rollingDice.map((d) => d.dieId).toSet();
      expect(ids, containsAll(['die-A', 'die-B']));
    });

    test('observer error in onDieRolling does not crash the roll session', () async {
      final throwing = RecordingObserver()..shouldThrowOnRolling = true;
      final env = await _setup(observers: [throwing]);

      env.die.fireRollState(DiceRollState.rolling);
      await Future.delayed(Duration.zero);
      // Settle the die so roll completes and we can check history.
      env.die.fireRollState(DiceRollState.rolled);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(env.rollDomain.rollHistory, hasLength(1));
    });
  });

  // ─── onRollComplete ───────────────────────────────────────────────────────

  group('onRollComplete', () {
    test('called after all dice settle', () async {
      final obs = RecordingObserver();
      final env = await _setup(observers: [obs]);
      await _doRoll(env.die);

      expect(obs.completedRolls, hasLength(1));
    });

    test('receives the dice that completed the roll', () async {
      final obs = RecordingObserver();
      final env = await _setup(observers: [obs]);
      await _doRoll(env.die);

      expect(obs.completedRolls.first.dice, isNotEmpty);
      expect(obs.completedRolls.first.dice.first.dieId, equals('die-A'));
    });

    test('receives a RollResult with the correct rollResult value', () async {
      final obs = RecordingObserver();
      final env = await _setup(observers: [obs]);
      env.die.state.currentFaceValue = 17;
      await _doRoll(env.die);

      expect(obs.completedRolls.first.result.rollResult, equals(17));
    });

    test('roll history is already populated when observer fires (Phase 2 before Phase 3)', () async {
      late int historyLengthDuringCallback;

      // Build a fresh rollDomain so we can capture rollHistory inside the callback.
      final dieDomain = RecordingDieDomain();
      final app = InMemoryAppService();
      final rp = RuleEvaluator(dieDomain, app, WebhookDomain(appService: app));
      await rp.init();
      late RollDomain rd;
      final checkObs = _HistoryCheckingObserver(
        onComplete: () => historyLengthDuringCallback = rd.rollHistory.length,
      );
      rd = await RollDomain.create(dieDomain, app, ruleParser: rp, observers: [checkObs]);

      final die = TestBleDie('die-A');
      dieDomain.emitDice({'die-A': die});
      await Future.delayed(Duration.zero);
      await _doRoll(die);

      expect(historyLengthDuringCallback, greaterThan(0),
          reason: 'result must be in rollHistory before observer fires (Phase 2 before Phase 3)');
    });

    test('observer error does not destroy the roll result', () async {
      final throwing = RecordingObserver()..shouldThrowOnComplete = true;
      final env = await _setup(observers: [throwing]);
      await _doRoll(env.die);

      expect(env.rollDomain.rollHistory, hasLength(1),
          reason: 'roll result must be preserved even when observer throws');
    });

    test('multiple observers each receive onRollComplete', () async {
      final obs1 = RecordingObserver();
      final obs2 = RecordingObserver();
      final env = await _setup(observers: [obs1, obs2]);
      await _doRoll(env.die);

      expect(obs1.completedRolls, hasLength(1));
      expect(obs2.completedRolls, hasLength(1));
    });

    test('second observer called even when first observer throws', () async {
      // Observers are fire-and-forget: all futures are started before any async
      // error can surface, so later observers are still called.
      final throwing = RecordingObserver()..shouldThrowOnComplete = true;
      final recording = RecordingObserver();
      final env = await _setup(observers: [throwing, recording]);
      await _doRoll(env.die);

      expect(recording.completedRolls, hasLength(1),
          reason: 'second observer must be called even if first throws');
    });
  });

  // ─── no observers ─────────────────────────────────────────────────────────

  group('no observers registered', () {
    test('roll completes normally with empty observer list', () async {
      final env = await _setup(observers: []);
      await _doRoll(env.die);

      expect(env.rollDomain.rollHistory, hasLength(1));
    });
  });
}

/// Calls a callback synchronously inside onRollComplete — used to snapshot
/// RollDomain state at the moment the observer fires.
class _HistoryCheckingObserver extends RollLifecycleObserver {
  final void Function() onComplete;
  _HistoryCheckingObserver({required this.onComplete});

  @override
  Future<void> onRollComplete(List<GenericDie> dice, RollResult result) async {
    onComplete();
  }
}
