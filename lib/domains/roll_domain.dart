import 'dart:async';

import 'package:collection/collection.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_parser/parser.dart';
import 'package:roll_feathers/domains/roll_parser/parser_rules.dart' as rule;
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
  late StreamSubscription<Map<String, GenericDie>> _deviceStreamListener; // used for notifications, better way?
  // final Map<String, Color> blinkColors = {};

  Timer? _rollUpdateTimer;

  late final RuleParser ruleParser;
  late final AppService appService;

  RollDomain._(this._diceDomain, this.appService) {
    _deviceStreamListener = _diceDomain.getDiceStream().listen(rollStreamListener);
    ruleParser = RuleParser(_diceDomain, this, appService);
  }

  Future<void> init() async {
    await ruleParser.init();
  }

  Stream<List<RollResult>> subscribeRollResults() => _rollResultStream.stream;

  Stream<RollStatus> subscribeRollStatus() => _rollStatusStream.stream;

  static Future<RollDomain> create(DieDomain dieDomain, AppService appService) async {
    var rollDomain = RollDomain._(dieDomain, appService);
    rollDomain.init();
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

  int _stopRollWithResult({RollType rollType = RollType.normal}) {
    ParseResult? ruleResult;
    // switch (rollType) {
    //   case RollType.max:
    //     ruleResult = ruleParser.runRule(rule.maxRoll, _rolledDie.values.toList());
    //   case RollType.min:
    //     ruleResult = ruleParser.runRule(rule.minRoll, _rolledDie.values.toList());
    //   default:
    //     for (var r in ruleParser.getRules(enabledOnly: true)) {
    //       ruleResult = ruleParser.runRule(r.script, _rolledDie.values.toList());
    //       if (ruleResult.ruleReturn) {
    //         rollType = RollType.rule;
    //         break;
    //       }
    //     }
    // }
    for (var r in ruleParser.getRules(enabledOnly: true)) {
      ruleResult = ruleParser.runRule(r.script, _rolledDie.values.toList());
      if (ruleResult.ruleReturn) {
        rollType = RollType.rule;
        break;
      }
    }
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
    var result = RollResult(rollType: rollType, rolls: resultRolls, rollResult: resultValue, ruleName: ruleName);
    _rollHistory.insert(0, result);
    _rollStatusStream.add(RollStatus.rollEnded);
    _rollResultStream.add(_rollHistory);
    return result.rollResult;
  }

  int _rollTotal() {
    return _rolledDie.values.map((d) => d.getFaceValueOrElse(orElse: 0)).fold(0, (p, c) => p + c);
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
      die.addRollCallback(DiceRollState.rolling, "$hashCode.rolling", (DiceRollState rollState) {
        // die has started rolling, initiate roll if its not already going
        if (!_isRolling) {
          _rollStartVirtualDice();
          _startRolling();
        }
      });

      die.addRollCallback(DiceRollState.rolled, "$hashCode.rolled", (DiceRollState rollState) {
        bool allDiceRolled = areDieRolling(data.values.where((d) => d.type != GenericDieType.virtual).toList());
        _rolledDie[die.dieId] = die;
        _rollEndVirtualDie();

        if (allDiceRolled && _isRolling) {
          // roll is active but all dice are done rolling
          _stopRolling();
          _stopRollWithResult();
        }
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
    Timer(const Duration(milliseconds: 500), () {
      _rollEndVirtualDie(force: force);
      _stopRolling();
      _stopRollWithResult(rollType: rollType);
    });
  }
}
