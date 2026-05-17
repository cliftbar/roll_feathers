import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/services/app_service.dart';

class RollResult {
  final RollType rollType;
  final int rollResult;
  final Map<String, int> rolls;
  late final DateTime _rollTime;
  final String? ruleName;

  RollResult({required this.rollType, required this.rollResult, required this.rolls, this.ruleName}) {
    _rollTime = DateTime.now();
  }

  DateTime get rollTime => _rollTime;

  Map<String, dynamic> toJson() {
    return {
      'rollType': rollType.name,
      'rollResult': rollResult,
      'rolls': rolls,
      'rollTime': rollTime.toIso8601String(),
    };
  }
}

enum RollType { sum, max, min, rule, normal }

enum RollStatus { rollStarted, rolling, rollEnded }

class RollDomain {
  final StreamController<List<RollResult>> _rollResultStream = StreamController<List<RollResult>>.broadcast();
  final StreamController<RollStatus> _rollStatusStream = StreamController<RollStatus>.broadcast();

  final List<RollResult> _rollHistory = [];

  List<RollResult> get rollHistory => _rollHistory;
  bool _isRolling = false;
  final Map<String, GenericDie> _rolledDie = {};
  RollType rollType = RollType.sum;
  bool autoRollVirtualDice = true;

  final DieDomain _diceDomain;
  // ignore: unused_field
  late StreamSubscription<Map<String, GenericDie>> _deviceStreamListener; // used for notifications, better way?
  // final Map<String, Color> blinkColors = {};

  Timer? _rollUpdateTimer;

  final Logger _log = Logger("RollDomain");
  final RuleEvaluator _ruleParser;
  final AppService appService;
  bool useAsyncEvaluator = false; // gated via AppService pref

  RollDomain._(this._diceDomain, this.appService, this._ruleParser) {
    _deviceStreamListener = _diceDomain.getDiceStream().listen(rollStreamListener);
  }

  Future<void> init() async {
    // Load evaluator preference (default false to avoid changing runtime behavior)
    try {
      useAsyncEvaluator = await appService.getUseAsyncEvaluator();
    } catch (_) {
      useAsyncEvaluator = false;
    }
  }

  Stream<List<RollResult>> subscribeRollResults() => _rollResultStream.stream;

  Stream<RollStatus> subscribeRollStatus() => _rollStatusStream.stream;

  static Future<RollDomain> create(DieDomain dieDomain, AppService appService,
      {required RuleEvaluator ruleParser}) async {
    var rollDomain = RollDomain._(dieDomain, appService, ruleParser);
    await rollDomain.init();
    return rollDomain;
  }

  bool areDieRolling(List<GenericDie> allDie) {
    return allDie.every(
      (d) => d.state.rollState == DiceRollState.rolled.index || d.state.rollState == DiceRollState.onFace.index,
    );
  }

  void _startRolling() {
    // reset roll state as needed
    _rolledDie.clear();
    _rollUpdateTimer?.cancel();

    _isRolling = true;
    _rollStatusStream.add(RollStatus.rollStarted);

    // periodically tell everyone that we're still rolling;

    _rollUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _rollStatusStream.add(RollStatus.rolling);
    });
  }

  void _stopRolling() {
    _rollUpdateTimer?.cancel();
    _isRolling = false;
    _rollStatusStream.add(RollStatus.rollEnded);
  }

  Future<int> _stopRollWithResult({RollType rollType = RollType.normal}) async {
    // Phase 1: pure evaluation — collect evaluations, no I/O
    final evaluations = <RuleEvaluation>[];
    ParseResult? ruleResult;
    for (var r in _ruleParser.getRules(enabledOnly: true)) {
      final eval = _ruleParser.evaluateRule(r.script, _rolledDie.values.toList());
      evaluations.add(eval);
      if (eval.result.ruleReturn) {
        ruleResult = eval.result;
        rollType = RollType.rule;
        break;
      }
    }

    // Phase 2: guaranteed recording — always runs
    late Map<String, int> resultRolls;
    late int resultValue;
    String? ruleName;
    if (ruleResult != null && ruleResult.ruleReturn) {
      resultRolls = ruleResult.allRolled;
      resultValue = ruleResult.result;
      ruleName = ruleResult.ruleName;
    } else {
      resultRolls = Map.fromEntries(_rolledDie.entries.map((e) => MapEntry(e.key, e.value.getFaceValueOrElse())));
      resultValue = resultRolls.values.sum;
    }
    final result = RollResult(rollType: rollType, rolls: resultRolls, rollResult: resultValue, ruleName: ruleName);
    _rollHistory.insert(0, result);
    _rollStatusStream.add(RollStatus.rollEnded);
    _rollResultStream.add(_rollHistory);

    // Phase 3: best-effort side effects — fire-and-forget, errors logged
    for (final eval in evaluations) {
      eval.fireEffects((e, st) => _log.warning('side effect error', e, st));
    }

    return result.rollResult;
  }


  void _rollStartVirtualDice({bool force = false}) {
    if (!autoRollVirtualDice && !force) {
      return;
    }
    _diceDomain.getVirtualDice().forEach((vd) => vd.setRollState(DiceRollState.rolling));
  }

  void _rollEndVirtualDie({bool force = false}) {
    if (!autoRollVirtualDice && !force) {
      return;
    }

    _diceDomain.getVirtualDice().forEach((vd) {
      vd.setRollState(DiceRollState.rolled);
      _rolledDie[vd.dieId] = vd;
    });
  }

  // attach listeners to die
  void rollStreamListener(Map<String, GenericDie> data) {
    for (var die in data.values.where((d) => d.type != GenericDieType.virtual)) {
      // Per-die flag: prevents re-sending blinkRolling if rolling fires multiple
      // times for the same die during a single roll session.
      bool dieBlinking = false;

      die.addRollCallback(DiceRollState.rolling, "$hashCode.rolling", (DiceRollState rollState) {
        if (!_isRolling) {
          _rollStartVirtualDice();
          _startRolling();
        }
        if (!dieBlinking) {
          dieBlinking = true;
          _diceDomain.blinkRolling(die);
        }
      });

      die.addRollCallback(DiceRollState.rolled, "$hashCode.rolled", (DiceRollState rollState) async {
        dieBlinking = false;
        await _diceDomain.stopAnimations(die);
        bool allDiceRolled = areDieRolling(data.values.where((d) => d.type != GenericDieType.virtual).toList());
        _rolledDie[die.dieId] = die;
        _rollEndVirtualDie();

        if (allDiceRolled && _isRolling) {
          // roll is active but all dice are done rolling
          _stopRolling();
          await _stopRollWithResult();
        }
      });

      die.addRollCallback(DiceRollState.crooked, "$hashCode.crooked", (DiceRollState rollState) async {
        dieBlinking = false;
        await _diceDomain.stopAnimations(die);
      });
    }
  }

  void clearRollResults() {
    _rollHistory.clear();
    _rollResultStream.add(_rollHistory);
  }

  void rollAllVirtualDice({bool force = false}) {
    if (_diceDomain.dieCount == 0) {
      return;
    }
    // Start the rolling process
    _startRolling();
    _rollStartVirtualDice(force: force);

    // Use a timer to simulate the rolling animation
    Timer(const Duration(milliseconds: 500), () async {
      _rollEndVirtualDie(force: force);
      _stopRolling();
      await _stopRollWithResult(rollType: rollType);
    });
  }
}
