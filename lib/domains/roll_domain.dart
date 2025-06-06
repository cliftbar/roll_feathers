import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';
import 'package:roll_feathers/domains/die_domain.dart';

class RollResult {
  final RollType rollType;
  final int rollResult;
  final List<int> rolls;
  late final DateTime _rollTime;

  RollResult({required this.rollType, required this.rollResult, required this.rolls}) {
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

enum RollType { sum, max, min }

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
  final Map<String, Color> blinkColors = {};

  Timer? _rollUpdateTimer;

  RollDomain._(this._diceDomain) {
    _deviceStreamListener = _diceDomain.getDiceStream().listen(rollStreamListener);
  }

  Stream<List<RollResult>> subscribeRollResults() => _rollResultStream.stream;
  Stream<RollStatus> subscribeRollStatus() => _rollStatusStream.stream;

  static Future<RollDomain> create(DieDomain rfController) async {
    return RollDomain._(rfController);
  }

  Color getRollingTextColor(PixelDie die, Color defaultColor) {
    switch (DiceRollState.values[die.state.rollState ?? 0]) {
      case DiceRollState.rolling:
      case DiceRollState.handling:
        return Colors.orange;
      case DiceRollState.onFace:
      case DiceRollState.rolled:
      default:
        return defaultColor;
    }
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

  int _stopRollWithResult({
    RollType rollType = RollType.sum,
    Color? advBlink = green,
    Color? disAdvBlink = red,
    Map<String, Color>? totalColors,
  }) {
    late int rollRet;
    switch (rollType) {
      case RollType.max:
        var maxRoll = _rolledDie.entries.reduce(
          (v, e) => v.value.getFaceValueOrElse() >= e.value.getFaceValueOrElse() ? v : e,
        );
        if (advBlink != null) {
          _diceDomain.blink(advBlink, maxRoll.value);
        }
        rollRet = maxRoll.value.getFaceValueOrElse();
      case RollType.min:
        var minRoll = _rolledDie.entries.reduce(
          (v, e) => v.value.getFaceValueOrElse() <= e.value.getFaceValueOrElse() ? v : e,
        );
        if (disAdvBlink != null) {
          _diceDomain.blink(disAdvBlink, minRoll.value);
        }
        rollRet = minRoll.value.getFaceValueOrElse();
      default:
        for (var die in _rolledDie.values) {
          _diceDomain.blink(blinkColors[die.dieId] ?? blue, die);
        }
        rollRet = _rollTotal();
    }
    var result = RollResult(
      rollType: rollType,
      rolls: _rolledDie.values.map((d) => d.getFaceValueOrElse()).toList(),
      rollResult: rollRet,
    );
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
    // TODO: something broken here for virtual dice
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
          _stopRollWithResult(rollType: rollType, totalColors: blinkColors);
        }
      });
    }
  }

  void clearRollResults() {
    _rollHistory.clear();
    _rollResultStream.add(_rollHistory);
  }

  void rollAllVirtualDice({bool force = false}) {
    // Start the rolling process
    _startRolling();
    _rollStartVirtualDice(force: force);

    // Use a timer to simulate the rolling animation
    Timer(const Duration(milliseconds: 500), () {
      _rollEndVirtualDie(force: force);
      _stopRolling();
      _stopRollWithResult(rollType: rollType, totalColors: blinkColors);
    });
  }
}
