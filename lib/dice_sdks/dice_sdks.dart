import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/godice.dart' as godice;
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;

class MessageParseError extends IOException {
  final String message;

  MessageParseError(this.message);
}

enum BatteryState { unknown, ok, low, transition, badCharging, error, charging, trickleCharge, done, lowTemp, highTemp }

class DiceState {
  int? rollState;
  int? currentFaceIndex;
  int? currentFaceValue;
  int? batteryLevel;
  BatteryState? batteryState;
  DateTime? lastRolled;

  DiceState({
    this.rollState,
    this.currentFaceIndex,
    this.currentFaceValue,
    this.batteryLevel,
    this.batteryState,
    this.lastRolled,
  });

  factory DiceState.fromJson(Map<String, dynamic> json) {
    return DiceState(
      rollState: json['rollState'] as int,
      currentFaceIndex: json['currentFaceIndex'] as int,
      currentFaceValue: json['currentFaceValue'] as int,
      batteryLevel: json['batteryLevel'] as int,
      batteryState: BatteryState.values[json['batteryState'] as int],
      lastRolled: DateTime.parse(json['lastRolled'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rollState': rollState,
      'currentFaceIndex': currentFaceIndex,
      'currentFaceValue': currentFaceValue,
      'batteryLevel': batteryLevel,
      'batteryState': batteryState,
      'lastRolled': lastRolled?.toIso8601String(),
    };
  }
}

enum DiceRollState { unknown, rolled, handling, rolling, crooked, onFace }

enum GenericDieType { pixel, godice }

abstract class GenericBleDie {
  abstract final Logger _log;
  abstract final GenericDieType type;
  BluetoothDevice device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  late DiceState state;
  List<String> haEntityTargets = [];

  static Future<GenericBleDie> fromDevice(BluetoothDevice device) async {
    try {
      await device.discoverServices();
      GenericBleDie die;
      var serviceIds = device.servicesList.map((e) => e.serviceUuid);
      var chars = device.servicesList.expand((s) => s.characteristics.map((c) => c.characteristicUuid));
      if (serviceIds.contains(pix.pixelsService) &&
          chars.contains(pix.pixelWriteCharacteristic) &&
          chars.contains(pix.pixelNotifyCharacteristic)) {
        die = PixelDie._(device: device);
        await die._init();
      } else if (serviceIds.contains(godice.godiceServiceGuid) &&
          chars.contains(godice.godiceWriteCharacteristic) &&
          chars.contains(godice.godiceNotifyCharacteristic)) {
        die = GoDiceBle(device: device);
        await die._init();
        // (die as GoDiceBle)._init();
      } else {
        throw Exception("not implemented");
      }

      await die._init();
      return die;
    } catch (e) {
      throw Exception('Failed to setup Die: $e');
    }
  }

  Future<void> _init();

  Map<int, Map<String, Function(RxMessage)>> messageRxCallbacks = {};
  Map<DiceRollState, Map<String, Function(DiceRollState)>> rollCallbacks = {};

  GenericBleDie({required this.device}) {
    state = DiceState();
  }

  Future<void> _sendMessageBuffer(List<int> data) async {
    try {
      await _writeChar?.write(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> sendMessage(TxMessage msg) async {
    await _sendMessageBuffer(msg.toBuffer());
  }

  // for overrides
  void _readNotify(List<int> data);

  void addMessageCallback(int messageType, String callbackKey, Function(RxMessage) callback) {
    messageRxCallbacks.putIfAbsent(messageType, () => {})[callbackKey] = callback;
  }

  void addRollCallback(DiceRollState rollState, String callbackKey, Function(DiceRollState) callback) {
    rollCallbacks.putIfAbsent(rollState, () => {})[callbackKey] = callback;
  }

  int getFaceValueOrElse({int orElse = -1}) {
    return state.currentFaceValue ?? orElse;
  }

  String get deviceId => device.remoteId.str;

  String get friendlyName;
}

class GoDiceBle extends GenericBleDie {
  final Map<String, dynamic> info = {};

  @override
  final _log = Logger("GoDiceBle");
  @override
  final GenericDieType type = GenericDieType.godice;

  GoDiceBle({required super.device});

  // 9007199254740991 is max on web, others are larger, but whatever, its big enough.
  static const int intMaxValue = 9000000000000000;

  int getClosestRollByVector(godice.Vector coord, godice.GodiceDieType dieType) {
    Map<int, godice.Vector> dieTypeVectorTable = godice.vectors[dieType]!;
    int minDistance = intMaxValue;
    int value = 0;
    godice.Vector result;

    // Calculating distance to each value in vector array
    for (int dieValue in dieTypeVectorTable.keys) {
      godice.Vector vector = dieTypeVectorTable[dieValue]!;

      result = godice.Vector(x: coord.x - vector.x, y: coord.y - vector.y, z: coord.z - vector.z);

      // Calculating squared magnitude (since it's only for comparing there's no need for sqrt)
      int curDist = ((result.x * result.x) + (result.y * result.y) + (result.z * result.z));

      if (curDist < minDistance) {
        minDistance = curDist;
        value = dieValue;
      }
    }
    return value;
  }

  @override
  void _readNotify(List<int> data) {
    _log.info(data);
    var msgType = godice.GodiceMessageType.getByValue(data[0]);
    switch (msgType) {
      case godice.GodiceMessageType.batteryLevelAck:
        godice.MessageBatteryLevelAck msg = godice.MessageBatteryLevelAck.parse(data);
        _updateStateBattery(msg);
        _log.fine('$friendlyName Received msg ${msgType.name}: ${json.encode(msg)}');
        _runMessageCallbacks(msg, msgType);
        break;
      case godice.GodiceMessageType.diceColorAck:
        godice.MessageDiceColorAck msg;
        try {
          msg = godice.MessageDiceColorAck.parse(data);
        } on MessageParseError catch (e) {
          _log.fine("$friendlyName bad message ${e.message}");
          return;
        }
        info["diceColor"] = msg.diceColor.name;
        _log.fine('$friendlyName Received msg ${msgType.name}: ${json.encode(msg)}');
        _runMessageCallbacks(msg, msgType);
        break;
      case godice.GodiceMessageType.stable:
        try {
          godice.MessageStable msg = godice.MessageStable.parse(data);
          _handleRollUpdate(msg.xyzData);
          _log.fine('$friendlyName Received msg ${msgType.name}: ${json.encode(msg)}');
          _runMessageCallbacks(msg, msgType);
          _runRollCallbacks(DiceRollState.rolled);
        } on MessageParseError catch (e) {
          _log.fine("$friendlyName error parsing message $data: $e");
        }
      case godice.GodiceMessageType.fakeStable:
        try {
          godice.MessageFakeStable msg = godice.MessageFakeStable.parse(data);
          _handleRollUpdate(msg.xyzData);
          _log.fine('$friendlyName Received msg ${msgType.name}: ${json.encode(msg)}');
          _runMessageCallbacks(msg, msgType);
          _runRollCallbacks(DiceRollState.rolled);
        } on MessageParseError catch (e) {
          _log.fine("$friendlyName error parsing message $data: $e");
        }
        break;
      case godice.GodiceMessageType.rollStart:
        godice.MessageRollStart msg = godice.MessageRollStart.parse(data);
        state.rollState = DiceRollState.rolling.index;
        _log.fine('$friendlyName Received msg ${msgType.name}: ${json.encode(msg)}');
        _runMessageCallbacks(msg, msgType);
        _runRollCallbacks(DiceRollState.rolling);
        break;
      default:
        var msg = godice.MessageUnknown.parse(data);
        _log.fine('$friendlyName Received msg ${msgType.name} data: ${msg.buffer}');
        _runMessageCallbacks(msg, godice.GodiceMessageType.unknown);
    }
  }

  void _handleRollUpdate(godice.Vector xyzData) {
    int currentRoll = getClosestRollByVector(xyzData, godice.GodiceDieType.d6);
    state.rollState = DiceRollState.rolled.index;
    state.currentFaceIndex = currentRoll - 1;
    state.currentFaceValue = currentRoll;
    state.lastRolled = DateTime.now();
  }

  void _runMessageCallbacks(RxMessage msg, godice.GodiceMessageType msgType) {
    if (messageRxCallbacks.containsKey(msgType.index)) {
      for (Function(RxMessage) func in (messageRxCallbacks[msgType.index]?.values ?? [])) {
        func(msg);
      }
    }
  }

  void _runRollCallbacks(DiceRollState rs) {
    if (rollCallbacks.containsKey(rs)) {
      for (Function(DiceRollState) func in (rollCallbacks[rs]?.values ?? [])) {
        func(rs);
      }
    }
  }

  void _updateStateBattery(godice.MessageBatteryLevelAck msg) {
    state.batteryLevel = msg.batteryLevel;
    state.batteryState = msg.batteryLevel < 20 ? BatteryState.low : BatteryState.ok;
  }

  @override
  Future<void> _init() async {
    _notifyChar?.onValueReceived.listen(_readNotify);
    await device.discoverServices();

    var service = device.servicesList.firstWhere((bs) => bs.serviceUuid == godice.godiceServiceGuid);
    _writeChar = service.characteristics.firstWhere((c) => c.uuid == godice.godiceWriteCharacteristic);
    _notifyChar = service.characteristics.firstWhere((c) => c.uuid == godice.godiceNotifyCharacteristic);

    await _notifyChar?.setNotifyValue(true);

    _sendMessageBuffer(godice.MessageInit().toBuffer());
    _sendMessageBuffer(godice.MessageDiceColor().toBuffer());
  }

  @override
  // TODO: implement friendlyName
  String get friendlyName => "GoDice ${info["diceColor"]}";
}

class PixelDie extends GenericBleDie {
  @override
  final _log = Logger("PixelDie");

  @override
  final GenericDieType type = GenericDieType.pixel;
  pix.PixelDiceInfo? info;

  PixelDie._({required super.device});

  @override
  void _readNotify(List<int> data) {
    var msgType = pix.PixelMessageType.values[data[0]];
    switch (msgType) {
      case pix.PixelMessageType.iAmADie:
        var msg = pix.MessageIAmADie.parse(data);
        _updateStateIAmADie(msg);
        _log.fine('Received msg ${msgType.name}: ${json.encode(msg)}');
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.batteryLevel:
        var msg = pix.MessageBatteryLevel.parse(data);
        _updateStateBattery(msg);
        _log.fine('Received msg ${msgType.name}: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.batteryLevel.index)) {
          for (Function(RxMessage) func
              in (messageRxCallbacks[pix.PixelMessageType.batteryLevel.index]?.values ?? [])) {
            func(msg);
          }
        }
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.rollState:
        var msg = pix.MessageRollState.parse(data);
        _updateStateRoll(msg);
        _log.fine('Received msg ${msgType.name}: ${DiceRollState.values[msg.rollState]} ${json.encode(msg)}');
        _runMessageCallbacks(msg, msgType);
        DiceRollState rollState =
            state.rollState != null ? DiceRollState.values[state.rollState!] : DiceRollState.unknown;
        _runRollCallbacks(rollState);
        break;
      default:
        var msg = pix.MessageNone.parse(data);
        _log.fine('Received msg ${msgType.name} data: ${msg.buffer}');
        _runMessageCallbacks(msg, msgType);
    }
    //
  }

  void _runMessageCallbacks(RxMessage msg, pix.PixelMessageType msgType) {
    if (messageRxCallbacks.containsKey(msgType.index)) {
      for (Function(RxMessage) func in (messageRxCallbacks[msgType.index]?.values ?? [])) {
        func(msg);
      }
    }
  }

  void _runRollCallbacks(DiceRollState rs) {
    if (rollCallbacks.containsKey(rs)) {
      for (Function(DiceRollState) func in (rollCallbacks[rs]?.values ?? [])) {
        func(rs);
      }
    }
  }

  void _updateStateIAmADie(pix.MessageIAmADie msg) {
    info ??= pix.PixelDiceInfo(
      ledCount: msg.ledCount,
      designAndColor: msg.designAndColor,
      reserved: msg.reserved,
      dataSetHash: msg.dataSetHash,
      pixelId: msg.pixelId,
      availableFlash: msg.availableFlash,
      buildTimestamp: msg.buildTimestamp,
    );

    state.rollState = msg.rollState;
    state.currentFaceIndex = msg.currentFaceIndex;
    state.currentFaceValue = msg.currentFaceValue;
    state.batteryLevel = msg.batteryLevel;
    state.batteryState = BatteryState.values[msg.batteryState];
  }

  void _updateStateBattery(pix.MessageBatteryLevel msg) {
    state.batteryLevel = msg.batteryLevel;
    state.batteryState = BatteryState.values[msg.batteryState];
  }

  void _updateStateRoll(pix.MessageRollState msg) {
    state.rollState = msg.rollState;
    state.currentFaceIndex = msg.currentFaceIndex;
    state.currentFaceValue = msg.currentFaceValue;
    state.lastRolled = DateTime.now();
  }

  @override
  Future<void> _init() async {
    _notifyChar?.onValueReceived.listen(_readNotify);

    var service = device.servicesList.firstWhere((bs) => bs.serviceUuid == pix.pixelsService);
    _writeChar = service.characteristics.firstWhere((c) => c.uuid == pix.pixelWriteCharacteristic);
    _notifyChar = service.characteristics.firstWhere((c) => c.uuid == pix.pixelNotifyCharacteristic);

    await _notifyChar?.setNotifyValue(true);

    await _sendMessageBuffer(pix.MessageWhoAreYou().toBuffer());
  }

  @override
  // TODO: implement friendlyName
  String get friendlyName => device.platformName;
}

// Messages
abstract class Message {
  final int id;

  Message({required this.id});

  static int bytesToIntList(List<int> bytes) {
    var result = 0;
    for (var i = 0; i < bytes.length; i++) {
      result |= bytes[i] << (8 * i);
    }
    return result;
  }
}

abstract class RxMessage extends Message {
  RxMessage({required this.buffer, required super.id});

  final List<int> buffer;
}

abstract class TxMessage extends Message {
  TxMessage({required super.id});

  List<int> toBuffer();
}

abstract class Blinker extends TxMessage with Color255 {
  Blinker({required super.id});

  int getCount();

  Duration getOnDuration();

  Duration getOffDuration();
}

mixin Color255 {
  Color getColor();

  int r255() {
    return (getColor().r * getColor().a * 255).toInt();
  }

  int g255() {
    return (getColor().g * getColor().a * 255).toInt();
  }

  int b255() {
    return (getColor().b * getColor().a * 255).toInt();
  }

  int a255() {
    return (getColor().a * 255).toInt();
  }
}
