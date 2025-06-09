import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../dice_sdks/godice.dart' as godice;
import '../dice_sdks/pixels.dart' as pix;
import '../repositories/ble/ble_repository.dart';
import 'message_sdk.dart';

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

enum GenericDieType { pixel, godice, virtual }

class DieFaceContainer {
  String dName;
  int faceCount;

  DieFaceContainer(this.dName, this.faceCount);
}

abstract class GenericDie {
  abstract final Logger _log;
  abstract final GenericDieType type;
  late DiceState state;
  List<String> haEntityTargets = [];

  Future<void> _init();

  Map<DiceRollState, Map<String, Function(DiceRollState)>> rollCallbacks = {};

  GenericDie() {
    state = DiceState();
    state.batteryLevel = 100;
    state.batteryState = BatteryState.unknown;
  }

  void addRollCallback(DiceRollState rollState, String callbackKey, Function(DiceRollState) callback) {
    rollCallbacks.putIfAbsent(rollState, () => {})[callbackKey] = callback;
  }

  int getFaceValueOrElse({int orElse = -1}) {
    return state.currentFaceValue ?? orElse;
  }

  String get dieId;

  String get friendlyName;

  DieFaceContainer get faceType;
  set faceType(DieFaceContainer df);
}

abstract class GenericBleDie extends GenericDie {
  BleDeviceWrapper device;

  Future<void> resetDevice(BleDeviceWrapper device) async {
    await device.init();
    device = device;
    await _init();
  }

  static Future<GenericBleDie> fromDevice(BleDeviceWrapper device) async {
    try {
      await device.init();
      GenericBleDie die;
      List<String> serviceIds = device.servicesUuids;
      List<String> chars = device.characteristicUuids;
      if (serviceIds.contains(pix.pixelsService) &&
          chars.contains(pix.pixelWriteCharacteristic) &&
          chars.contains(pix.pixelNotifyCharacteristic)) {
        die = PixelDie._(device: device);
        await die._init();
      } else if (serviceIds.contains(godice.godiceServiceGuid) &&
          chars.contains(godice.godiceWriteCharacteristic) &&
          chars.contains(godice.godiceNotifyCharacteristic)) {
        die = GoDiceBle(device: device, dieFaceType: godice.GodiceDieType.d6);
        await die._init();
      } else {
        throw Exception("Bluetooth Device Not Implemented");
      }

      await die._init();
      return die;
    } catch (e) {
      throw Exception('Failed to setup Die: $e');
    }
  }

  Map<int, Map<String, Function(RxMessage)>> messageRxCallbacks = {};

  GenericBleDie({required this.device}) {
    state = DiceState();
  }

  Future<void> _sendMessageBuffer(List<int> data) async {
    try {
      device.writeMessage(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> sendMessage(TxMessage msg) async {
    await _sendMessageBuffer(msg.toBuffer());
  }

  // keeo for overrides!!
  void _readNotify(List<int> data);

  void addMessageCallback(int messageType, String callbackKey, Function(RxMessage) callback) {
    messageRxCallbacks.putIfAbsent(messageType, () => {})[callbackKey] = callback;
  }

  @override
  String get dieId => device.deviceId;

  @override
  String get friendlyName;
}

class GoDiceBle extends GenericBleDie {
  // 9007199254740991 is max on web, others are larger, but whatever, its big enough.
  static const int intMaxValue = 9000000000000000;

  final Map<String, dynamic> info = {};

  @override
  final _log = Logger("GoDiceBle");
  @override
  final GenericDieType type = GenericDieType.godice;

  final String _godiceFaceTypeKey = "dieFaceType";
  final String _dieFaceContainerKey = "dieFaceContainer";

  GoDiceBle({required godice.GodiceDieType dieFaceType, required super.device}) {
    DieFaceContainer df = DieFaceContainer(dieFaceType.name, dieFaceType.faces);
    info[_godiceFaceTypeKey] = dieFaceType;
    info[_dieFaceContainerKey] = df;
  }

  int getClosestRollByVector(godice.Vector coord, godice.GodiceDieType dieType) {
    Map<int, godice.Vector> dieTypeVectorTable = godice.vectors[godice.vectorToTransform[dieType]]!;
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

    if (godice.transforms.containsKey(dieType)) {
      value = godice.transforms[dieType]![value]!;
    }

    return value;
  }

  @override
  void _readNotify(List<int> data) {
    _log.finer(data);
    var msgType = godice.GodiceMessageType.getByValue(data);
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
      case godice.GodiceMessageType.tiltStable:
        try {
          godice.MessageTiltStable msg = godice.MessageTiltStable.parse(data);
          _handleRollUpdate(msg.xyzData);
          _log.fine('$friendlyName Received msg ${msgType.name}: ${json.encode(msg)}');
          _runMessageCallbacks(msg, msgType);
          _runRollCallbacks(DiceRollState.rolled);
        } on MessageParseError catch (e) {
          _log.fine("$friendlyName error parsing message $data: $e");
        }
        break;
      case godice.GodiceMessageType.moveStable:
        try {
          godice.MessageMoveStable msg = godice.MessageMoveStable.parse(data);
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
    int currentRoll = getClosestRollByVector(xyzData, info[_godiceFaceTypeKey]);
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
    await device.setDeviceUuids(
      serviceUuid: godice.godiceServiceGuid,
      notifyUuid: godice.godiceNotifyCharacteristic,
      writeUuid: godice.godiceWriteCharacteristic,
    );
    device.notifyStream.listen(_readNotify);

    _sendMessageBuffer(godice.MessageInit().toBuffer());
    _sendMessageBuffer(godice.MessageDiceColor().toBuffer());
  }

  @override
  String get friendlyName => "GoDice ${info["diceColor"]}";

  @override
  DieFaceContainer get faceType => info[_dieFaceContainerKey];

  @override
  set faceType(DieFaceContainer df) {
    info[_dieFaceContainerKey] = df;
  }
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
      pixelDieTypeFaces: msg.pixelDieTypeFaces,
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
    await device.setDeviceUuids(
      serviceUuid: pix.pixelsService,
      notifyUuid: pix.pixelNotifyCharacteristic,
      writeUuid: pix.pixelWriteCharacteristic,
    );
    device.notifyStream.listen(_readNotify);
    await Future.delayed(Duration(milliseconds: 100)); // sleep needed on web??
    await _sendMessageBuffer(pix.MessageWhoAreYou().toBuffer());
  }

  @override
  String get friendlyName => device.friendlyName;

  @override
  DieFaceContainer get faceType {
    pix.PixelDieType dt = info?.pixelDieTypeFaces ?? pix.PixelDieType.unknown;

    return DieFaceContainer(dt.name, dt.faces);
  }

  @override
  set faceType(DieFaceContainer faces) {
    throw UnsupportedError("pixel die can't change faces");
  }
}

class VirtualDie extends GenericDie {
  @override
  final _log = Logger("VirtualDie");

  late final String _dieId;
  late final String? _name;
  late int _faceCount;
  final Random rand = Random();

  @override
  final GenericDieType type = GenericDieType.virtual;

  VirtualDie({required faceCount, String? dieId, String? name}) {
    _dieId = dieId ?? Uuid().v4();
    _name = name;
    state.currentFaceValue = 1;
    state.currentFaceIndex = 0;
    _faceCount = faceCount;
  }

  @override
  String get dieId => _dieId;

  void setRollState(DiceRollState rs) {

    if ((rs == DiceRollState.rolled || rs == DiceRollState.onFace) && state.rollState == DiceRollState.rolling.index) {

      state.currentFaceIndex = rand.nextInt(_faceCount);
      state.currentFaceValue = state.currentFaceIndex! + 1;
    }
    state.rollState = rs.index;
    _runRollCallbacks(rs);
  }

  void _runRollCallbacks(DiceRollState rs) {
    if (rollCallbacks.containsKey(rs)) {
      for (Function(DiceRollState) func in (rollCallbacks[rs]?.values ?? [])) {
        func(rs);
      }
    }
  }

  @override
  Future<void> _init() async {}

  @override
  String get friendlyName => _name ?? dieId;

  @override
  DieFaceContainer get faceType {
    return DieFaceContainer("d$_faceCount", _faceCount);
  }

  @override
  set faceType(DieFaceContainer faces) {
    _faceCount = faces.faceCount;
  }
}
