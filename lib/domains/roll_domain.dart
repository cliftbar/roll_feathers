import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/pixel_die_domain.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart';

import 'package:roll_feathers/dice_sdks/generic_die.dart';

class RollResult {
  final RollType rollType;
  final int rollResult;
  late final DateTime rollTime;

  RollResult({required this.rollType, required this.rollResult}) {
    rollTime = DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {'rollType': rollType.name, 'rollResult': rollResult, 'rollTime': rollTime.toIso8601String()};
  }
}

enum RollType { sum, advantage, disadvantage }

enum RollStatus { rollStarted, rolling, rollEnded }

class RollDomain {
  final StreamController<List<RollResult>> _rollResultStream = StreamController<List<RollResult>>.broadcast();
  final StreamController<RollStatus> _rollStatusStream = StreamController<RollStatus>.broadcast();

  final List<RollResult> _rollHistory = [];

  List<RollResult> get rollHistory => _rollHistory;
  bool _isRolling = false;
  final Map<String, GenericBleDie> _rollingDie = {};
  RollType rollType = RollType.sum;

  final PixelDieDomain _rollFeathersController;
  late StreamSubscription<Map<String, GenericBleDie>> _deviceStreamListener;
  final Map<String, Color> blinkColors = {};

  Timer? _rollUpdateTimer;

  RollDomain._(this._rollFeathersController) {
    _deviceStreamListener = _rollFeathersController.getDeviceStream().listen(rollStreamListener);
  }

  Stream<List<RollResult>> subscribeRollResults() => _rollResultStream.stream;
  Stream<RollStatus> subscribeRollStatus() => _rollStatusStream.stream;

  static Future<RollDomain> create(PixelDieDomain rfController) async {
    return RollDomain._(rfController);
  }

  Color getRollingTextColor(PixelDie die, Color defaultColor) {
    switch (PixelRollState.values[die.state.rollState ?? 0]) {
      case PixelRollState.rolling:
      case PixelRollState.handling:
        return Colors.orange;
      case PixelRollState.onFace:
      case PixelRollState.rolled:
      default:
        return defaultColor;
    }
  }

  bool areDieRolling(List<GenericBleDie> allDie) {
    return allDie.every(
      (d) => d.state.rollState == PixelRollState.rolled.index || d.state.rollState == PixelRollState.onFace.index,
    );
  }

  void _startRolling() {
    // reset roll state as needed
    _rollingDie.clear();
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
      case RollType.advantage:
        var maxRoll = _rollingDie.entries.reduce(
          (v, e) => v.value.getFaceValueOrElse() >= e.value.getFaceValueOrElse() ? v : e,
        );
        if (advBlink != null) {
          _rollFeathersController.blink(advBlink, maxRoll.value);
        }
        rollRet = maxRoll.value.getFaceValueOrElse();
      case RollType.disadvantage:
        var minRoll = _rollingDie.entries.reduce(
          (v, e) => v.value.getFaceValueOrElse() <= e.value.getFaceValueOrElse() ? v : e,
        );
        if (disAdvBlink != null) {
          _rollFeathersController.blink(disAdvBlink, minRoll.value);
        }
        rollRet = minRoll.value.getFaceValueOrElse();
      default:
        for (var die in _rollingDie.values) {
          _rollFeathersController.blink(blinkColors[die.deviceId] ?? blue, die);
        }
        rollRet = _rollTotal();
    }
    var result = RollResult(rollType: rollType, rollResult: rollRet);
    _rollHistory.insert(0, result);
    _rollStatusStream.add(RollStatus.rollEnded);
    _rollResultStream.add(_rollHistory);
    return result.rollResult;
  }

  int _rollTotal() {
    return _rollingDie.values.map((d) => d.getFaceValueOrElse(orElse: 0)).fold(0, (p, c) => p + c);
  }

  // attach listeners to die
  void rollStreamListener(Map<String, GenericBleDie> data) {
    for (var die in data.values) {
      die.addMessageCallback(PixelMessageType.rollState.index, "$this.hashCode", (msg) {
        MessageRollState rollStateMsg = msg as MessageRollState;
        if (rollStateMsg.rollState == PixelRollState.rolled.index || rollStateMsg.rollState == PixelRollState.onFace.index) {
          // _rollingColors[die.device.remoteId.toString()] = Colors.green;

          bool allDiceRolled = areDieRolling(data.values.toList());
          _rollingDie[die.device.remoteId.str] = die;

          if (allDiceRolled && _isRolling) {
            // roll is active but all dice are done rolling
            _stopRolling();
            _stopRollWithResult(rollType: rollType, totalColors: blinkColors);
          }
        } else if (rollStateMsg.rollState == PixelRollState.rolling.index) {
          // die has started rolling, initiate roll if its not already going
          if (!_isRolling) {
            _startRolling();
          }
        }
      });
    }
  }

  void clearRollResults() {
    _rollHistory.clear();
    _rollResultStream.add(_rollHistory);
  }
}
