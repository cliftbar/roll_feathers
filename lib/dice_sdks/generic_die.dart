import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/godice.dart' as godice;
import 'package:roll_feathers/dice_sdks/godice_ai.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;

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

enum GenericDieType {
  pixel,
  godice
}

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
      if (serviceIds.contains(pix.pixelsService) && chars.contains(pix.pixelWriteCharacteristic) && chars.contains(pix.pixelNotifyCharacteristic)) {
        die = PixelDie._(device: device);
        await die._init();
      } else if (serviceIds.contains(GoDice.SERVICE_UUID) && chars.contains(GoDice.TX_CHARACTERISTIC_UUID) && chars.contains(GoDice.RX_CHARACTERISTIC_UUID)) {
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

  GenericBleDie({required this.device}){
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

  void _readNotify(List<int> data);

  List<int> listUint8ToInt(List<int> lIn) {
    return List.of(lIn.map((e) => e as int));
  }

  void addMessageCallback(int messageType, String callbackKey, Function(RxMessage) callback) {
    messageRxCallbacks.putIfAbsent(messageType, () => {})[callbackKey] = callback;
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

  @override
  void _readNotify(List<int> dataBytes) {
    var data = listUint8ToInt(dataBytes);
    _log.info(data);
    var msgType = godice.GodiceMessageType.getByValue(data[0]);
    switch (msgType) {
      case godice.GodiceMessageType.batteryLevelAck:
        var msg = godice.MessageBatteryLevelAck.parse(data);
        _updateStateBattery(msg);
        _log.fine('Received msg ${godice.GodiceMessageType.batteryLevelAck.name}: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(godice.GodiceMessageType.batteryLevelAck.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[godice.GodiceMessageType.batteryLevelAck.index]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      case godice.GodiceMessageType.diceColorAck:
        var msg = godice.MessageDiceColorAck.parse(data);
        info["diceColor"] = msg.diceColor.name;
        print('Received msg ${godice.GodiceMessageType.diceColorAck.name}: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(godice.GodiceMessageType.diceColorAck.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[godice.GodiceMessageType.diceColorAck.index]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      default:
        var msg = godice.MessageUnknown.parse(data);
        print('Received data: ${msg.buffer}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.none.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[pix.PixelMessageType.none.index]?.values ?? [])) {
            func(msg);
          }
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

    var service = device.servicesList.firstWhere((bs) => bs.serviceUuid == GoDice.SERVICE_UUID);
    _writeChar = service.characteristics.firstWhere((c) => c.uuid == GoDice.TX_CHARACTERISTIC_UUID);
    _notifyChar = service.characteristics.firstWhere((c) => c.uuid == GoDice.RX_CHARACTERISTIC_UUID);

    await _notifyChar?.setNotifyValue(true);

    _sendMessageBuffer(godice.MessageBatteryLevel().toBuffer());
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
        _log.fine('Received msg IAmADie: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.iAmADie.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[pix.PixelMessageType.iAmADie.index]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      case pix.PixelMessageType.batteryLevel:
        var msg = pix.MessageBatteryLevel.parse(data);
        _updateStateBattery(msg);
        _log.fine('Received msg BatteryLevel: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.batteryLevel.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[pix.PixelMessageType.batteryLevel.index]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      case pix.PixelMessageType.rollState:
        var msg = pix.MessageRollState.parse(data);
        _updateStateRoll(msg);
        _log.fine('Received msg RollState: ${pix.PixelRollState.values[msg.rollState]} ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.rollState.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[pix.PixelMessageType.rollState.index]?.values ?? [])) {
            func(msg);
          }
        }
        break;
      default:
        var msg = pix.MessageNone.parse(data);
        _log.fine('Received data: ${msg.buffer}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.none.index)) {
          for (Function(RxMessage) func in (messageRxCallbacks[pix.PixelMessageType.none.index]?.values ?? [])) {
            func(msg);
          }
        }
    }
    //
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

abstract class Blinker with Color255 {
  int getCount();

  int getDuration();

  int getLoopCount();
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
