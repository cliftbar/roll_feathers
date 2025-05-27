import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';

class DiceInfo {
  final int ledCount;
  final int designAndColor;
  final int reserved;
  final int dataSetHash;
  final int pixelId;
  final int availableFlash;
  final int buildTimestamp;

  DiceInfo({
    required this.ledCount,
    required this.designAndColor,
    required this.reserved,
    required this.dataSetHash,
    required this.pixelId,
    required this.availableFlash,
    required this.buildTimestamp,
  });

  factory DiceInfo.fromJson(Map<String, dynamic> json) {
    return DiceInfo(
      ledCount: json['ledCount'] as int,
      designAndColor: json['designAndColor'] as int,
      reserved: json['reserved'] as int,
      dataSetHash: json['dataSetHash'] as int,
      pixelId: json['pixelId'] as int,
      availableFlash: json['availableFlash'] as int,
      buildTimestamp: json['buildTimestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ledCount': ledCount,
      'designAndColor': designAndColor,
      'reserved': reserved,
      'dataSetHash': dataSetHash,
      'pixelId': pixelId,
      'availableFlash': availableFlash,
      'buildTimestamp': buildTimestamp,
    };
  }
}

class DiceState {
  int? rollState;
  int? currentFaceIndex;
  int? currentFaceValue;
  int? batteryLevel;
  int? batteryState;
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
      batteryState: json['batteryState'] as int,
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

class PixelDie {
  final log = Logger("PixelDie");
  BluetoothDevice device;
  BluetoothCharacteristic writeChar;
  BluetoothCharacteristic notifyChar;
  DiceInfo? info;
  late DiceState state;
  List<String> haEntityTargets = [];

  Map<MessageType, Map<String, Function(RxMessage)>> messageRxCallbacks = {};

  PixelDie._({required this.device, required this.writeChar, required this.notifyChar}) {
    state = DiceState();
    notifyChar.onValueReceived.listen(_readNotify);
    // Send IAmADie request message (0x01)
    _sendMessageBuffer(MessageWhoAreYou().toBuffer());
  }

  static Future<PixelDie> fromDevice(BluetoothDevice device) async {
    try {
      await device.discoverServices();

      var service = device.servicesList.firstWhere((bs) => bs.serviceUuid == pixelsService);
      var writeChar = service.characteristics.firstWhere((c) => c.uuid == pixelWriteCharacteristic);
      var notifyChar = service.characteristics.firstWhere((c) => c.uuid == pixelNotifyCharacteristic);

      await notifyChar.setNotifyValue(true);

      var die = PixelDie._(device: device, writeChar: writeChar, notifyChar: notifyChar);
      await die._sendMessageBuffer(MessageWhoAreYou().toBuffer());
      return die;
    } catch (e) {
      throw Exception('Failed to setup PixelDie: $e');
    }
  }

  Future<void> _sendMessageBuffer(List<int> data) async {
    try {
      await writeChar.write(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> sendMessage(TxMessage msg) async {
    await _sendMessageBuffer(msg.toBuffer());
  }

  void _readNotify(List<int> data) {
    var msgType = MessageType.values[data[0]];
    switch (msgType) {
      case MessageType.iAmADie:
        var msg = MessageIAmADie.parse(data);
        _updateStateIAmADie(msg);
        log.fine('Received msg IAmADie: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(MessageType.iAmADie)) {
          for (Function(RxMessage) func in (messageRxCallbacks[MessageType.iAmADie]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      case MessageType.batteryLevel:
        var msg = MessageBatteryLevel.parse(data);
        _updateStateBattery(msg);
        log.fine('Received msg BatteryLevel: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(MessageType.batteryLevel)) {
          for (Function(RxMessage) func in (messageRxCallbacks[MessageType.batteryLevel]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      case MessageType.rollState:
        var msg = MessageRollState.parse(data);
        _updateStateRoll(msg);
        log.fine('Received msg RollState: ${RollState.values[msg.rollState]} ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(MessageType.rollState)) {
          for (Function(RxMessage) func in (messageRxCallbacks[MessageType.rollState]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      default:
        var msg = MessageNone.parse(data);
        log.fine('Received data: ${msg.buffer}');
        if (messageRxCallbacks.containsKey(MessageType.none)) {
          for (Function(RxMessage) func in (messageRxCallbacks[MessageType.none]?.values ?? [])) {
            func(msg);
          }
        }
    }
    //
  }

  void addMessageCallback(MessageType messageType, String callbackKey, Function(RxMessage) callback) {
    messageRxCallbacks.putIfAbsent(messageType, () => {})[callbackKey] = callback;
  }

  void _updateStateIAmADie(MessageIAmADie msg) {
    info ??= DiceInfo(
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
    state.batteryState = msg.batteryState;
  }

  void _updateStateBattery(MessageBatteryLevel msg) {
    state.batteryLevel = msg.batteryLevel;
    state.batteryState = msg.batteryState;
  }

  void _updateStateRoll(MessageRollState msg) {
    state.rollState = msg.rollState;
    state.currentFaceIndex = msg.currentFaceIndex;
    state.currentFaceValue = msg.currentFaceValue;
    state.lastRolled = DateTime.now();
  }

  int getFaceValueOrElse({int orElse = -1}) {
    return state.currentFaceValue ?? orElse;
  }

  String get deviceId => device.remoteId.str;
}
