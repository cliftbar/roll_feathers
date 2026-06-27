import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'package:roll_feathers/dice_sdks/godice.dart' as godice;
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart' as pix;
import 'package:roll_feathers/repositories/ble/ble_repository.dart';

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

class GenericDType {
  final String name;
  final int intId;
  final int faces;
  final int multiplier;
  final int indexOffset;

  const GenericDType(this.name, this.intId, this.faces, this.indexOffset, this.multiplier);
}

class GenericDTypeFactory {
  static final String unknown = "unknown";
  static final String d4 = "d4";
  static final String d6 = "d6";
  static final String d8 = "d8";
  static final String d10 = "d10";
  static final String d00 = "d00";
  static final String d12 = "d12";
  static final String d20 = "d20";
  static final Map<String, GenericDType> _wellKnown = {
    unknown: GenericDType("unknown", -1, -1, 0, 1),
    d4: GenericDType("d4", 4, 4, 1, 1),
    d6: GenericDType("d6", 6, 6, 1, 1),
    d8: GenericDType("d8", 8, 8, 1, 1),
    d10: GenericDType("d10", 10, 10, 1, 1),
    d00: GenericDType("d00", 0, 10, 0, 10),
    d12: GenericDType("d12", 12, 12, 1, 1),
    d20: GenericDType("d20", 20, 20, 1, 1),
  };

  static GenericDType getKnownChecked(String name) {
    return _wellKnown[name] ?? _wellKnown[unknown]!;
  }

  static GenericDType? getKnown(String name) {
    return _wellKnown[name];
  }

  static GenericDType? fromIntId(int intId) {
    return _wellKnown.values.firstWhereOrNull((v) => v.intId == intId);
  }
}

/// Animation preset for the rolling flash feature.
enum RollingFlashPreset {
  strobe,  // 50ms on / 50ms off / fade 0
  pulse,   // 400ms on / 200ms off / fade 0
  breathe, // 600ms on / 600ms off / fade 128
}

abstract class GenericDie {
  abstract final GenericDieType type;
  late DiceState state;
  List<String> haEntityTargets = [];

  // Rolling flash — per-die settings (Pixels only; ignored by other types).
  bool rollingFlashEnabled = false;
  Color? rollingFlashColor;
  RollingFlashPreset rollingFlashPreset = RollingFlashPreset.strobe;

  Color? get blinkColor;

  set blinkColor(Color? c);

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
  set friendlyName(String name);

  GenericDType get dType;

  set dType(GenericDType df);
}

abstract class GenericBleDie extends GenericDie {
  BleDeviceWrapper device;
  VoidCallback? onStateChanged;
  StreamSubscription<List<int>>? _notifySubscription;

  /// App-side name override. Takes precedence over the BLE-advertised name so a
  /// rename reflects immediately (before the die re-advertises) and a persisted
  /// name restores on reconnect.
  String? _friendlyNameOverride;
  @override
  set friendlyName(String name) => _friendlyNameOverride = name;

  void dispose() {
    _notifySubscription?.cancel();
  }

  Future<void> resetDevice(BleDeviceWrapper device) async {
    await device.init();
    device = device;
    await _init();
  }

  static final _fromDeviceLog = Logger("GenericBleDie");

  static Future<GenericBleDie> fromDevice(BleDeviceWrapper device) async {
    try {
      await device.init();
      GenericBleDie die;
      List<String> serviceIds = device.servicesUuids;
      List<String> chars = device.characteristicUuids;
      _fromDeviceLog.info('fromDevice ${device.friendlyName}: services=${serviceIds.join(',')} chars=${chars.join(',')}');
      // GoDice and Pixels share the same NUS service and characteristic UUIDs,
      // so use device name to disambiguate. The BLE repository caches names
      // across scans so that Android re-scans (which may return null names even
      // for namePrefix-matched devices) still resolve correctly.
      if (//device.friendlyName.startsWith('GoDice_') &&
          serviceIds.contains(godice.godiceServiceGuid) &&
          chars.contains(godice.godiceWriteCharacteristic) &&
          chars.contains(godice.godiceNotifyCharacteristic)) {
        die = GoDiceBle(device: device, dieFaceType: godice.GodiceDieType.d6);
        await die._init();
      } else if (serviceIds.contains(pix.pixelsService) &&
          chars.contains(pix.pixelWriteCharacteristic) &&
          chars.contains(pix.pixelNotifyCharacteristic)) {
        die = PixelDie._(device: device);
        await die._init();
      } else {
        throw Exception("Bluetooth Device Not Implemented");
      }

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
      await device.writeMessage(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> sendMessage(TxMessage msg) async {
    await _sendMessageBuffer(msg.toBuffer());
  }

  // ignore: unused_element — abstract contract for subclasses; analyzer can't see override-only usage
  void _readNotify(List<int> data);

  void addMessageCallback(int messageType, String callbackKey, Function(RxMessage) callback) {
    messageRxCallbacks.putIfAbsent(messageType, () => {})[callbackKey] = callback;
  }

  @override
  String get dieId => device.deviceId;

  @override
  String get friendlyName => _friendlyNameOverride ?? device.friendlyName;
}

class GoDiceBle extends GenericBleDie {
  // 9007199254740991 is max on web, others are larger, but whatever, its big enough.
  static const int intMaxValue = 9000000000000000;

  final Map<String, dynamic> info = {};

  final _log = Logger("GoDiceBle");
  @override
  final GenericDieType type = GenericDieType.godice;

  final String _godiceFaceTypeKey = "dieFaceType";
  final String _dTypeContainerKey = "dieFaceContainer";
  Color? _blinkColor;

  static Future<GoDiceBle> create({required godice.GodiceDieType dieFaceType, required BleDeviceWrapper device}) async {
    GoDiceBle ret = GoDiceBle(dieFaceType: dieFaceType, device: device);
    await ret._init();
    return ret;
  }

  GoDiceBle({required godice.GodiceDieType dieFaceType, required super.device}) {
    GenericDType df = dieFaceType.toDType();
    info[_godiceFaceTypeKey] = dieFaceType;
    info[_dTypeContainerKey] = df;
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
        onStateChanged?.call();
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
        onStateChanged?.call();
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
      for (Function(RxMessage) func in List.of(messageRxCallbacks[msgType.index]?.values ?? [])) {
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
    _notifySubscription = device.notifyStream.listen(
      _readNotify,
      onError: (e) => _log.severe('notify stream error: $e'),
    );

    await _sendMessageBuffer(godice.MessageInit().toBuffer());
    await _sendMessageBuffer(godice.MessageDiceColor().toBuffer());
  }

  @override
  String get friendlyName => "GoDice ${info["diceColor"]}";

  @override
  GenericDType get dType => info[_dTypeContainerKey];

  @override
  set dType(GenericDType df) {
    info[_godiceFaceTypeKey] = godice.GodiceDieType.fromName(df.name);
    info[_dTypeContainerKey] = df;
  }

  @override
  // TODO: implement blinkColor
  Color? get blinkColor => _blinkColor;

  @override
  set blinkColor(Color? c) {
    _blinkColor = c;
  }
}

class PixelDie extends GenericBleDie {
  final _log = Logger("PixelDie");

  @override
  final GenericDieType type = GenericDieType.pixel;
  pix.PixelDiceInfo? info;

  Color? _blinkColor;

  static Future<PixelDie> create({required BleDeviceWrapper device}) async {
    PixelDie ret = PixelDie._(device: device);
    await ret._init();
    return ret;
  }

  PixelDie._({required super.device});

  @override
  void _readNotify(List<int> data) {
    if (data.isEmpty || data[0] >= pix.PixelMessageType.values.length) {
      _log.fine('Received unknown Pixels message type: ${data.isEmpty ? 'empty' : data[0]}, ignoring');
      return;
    }
    var msgType = pix.PixelMessageType.values[data[0]];
    switch (msgType) {
      case pix.PixelMessageType.iAmADie:
        var msg = pix.MessageIAmADie.parse(data);
        _updateStateIAmADie(msg);
        _log.fine('Received msg ${msgType.name}: ${json.encode(msg)}');
        _runMessageCallbacks(msg, msgType);
        onStateChanged?.call();
        break;
      case pix.PixelMessageType.batteryLevel:
        var msg = pix.MessageBatteryLevel.parse(data);
        _updateStateBattery(msg);
        _log.fine('Received msg ${msgType.name}: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(pix.PixelMessageType.batteryLevel.index)) {
          for (Function(RxMessage) func
              in List.of(messageRxCallbacks[pix.PixelMessageType.batteryLevel.index]?.values ?? [])) {
            func(msg);
          }
        }
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.rollState:
        var msg = pix.MessageRollState.parse(data);
        _updateStateRoll(msg);
        _log.fine('RollState telemetry: ${DiceRollState.values[msg.rollState]} face=${msg.currentFaceValue}');
        _runMessageCallbacks(msg, msgType);
        DiceRollState rollState =
            state.rollState != null ? DiceRollState.values[state.rollState!] : DiceRollState.unknown;
        _runRollCallbacks(rollState);
        break;
      case pix.PixelMessageType.transferAnimationSetAck:
        final msg = pix.MessageTransferAnimationSetAck.parse(data);
        _log.fine('Received msg ${msgType.name}: result=${msg.result}');
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.transferAnimationSetFinished:
        final msg = pix.MessageTransferAnimationSetFinished.parse(data);
        _log.fine('Received msg ${msgType.name}');
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.bulkSetupAck:
        final msg = pix.MessageBulkSetupAck.parse(data);
        _log.fine('Received msg ${msgType.name}');
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.bulkDataAck:
        final msg = pix.MessageBulkDataAck.parse(data);
        _log.fine('Received msg ${msgType.name}: offset=${msg.offset}');
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.transferInstantAnimationSetAck:
        final msg = pix.MessageTransferInstantAnimationSetAck.parse(data);
        _log.fine('Received msg ${msgType.name}: ackType=${msg.ackType}');
        _runMessageCallbacks(msg, msgType);
        break;
      case pix.PixelMessageType.transferInstantAnimationSetFinished:
        final msg = pix.MessageTransferInstantAnimationSetFinished.parse(data);
        _log.fine('Received msg ${msgType.name}');
        _runMessageCallbacks(msg, msgType);
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
      for (Function(RxMessage) func in List.of(messageRxCallbacks[msgType.index]?.values ?? [])) {
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
    _log.fine('IAmADie dataSetHash=0x${msg.dataSetHash.toUnsigned(32).toRadixString(16).toUpperCase().padLeft(8, '0')} firmware=${msg.buildTimestamp}');
    info = pix.PixelDiceInfo(
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
    _notifySubscription = device.notifyStream.listen(
      _readNotify,
      onError: (e) => _log.severe('notify stream error: $e'),
    );

    final completer = Completer<void>();
    addMessageCallback(pix.PixelMessageType.iAmADie.index, '_init', (_) {
      if (!completer.isCompleted) completer.complete();
    });

    await Future.delayed(Duration(milliseconds: 100)); // sleep needed on web??
    await _sendMessageBuffer(pix.MessageWhoAreYou().toBuffer());

    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _log.warning('IAmADie not received within 5s during init');
    } finally {
      messageRxCallbacks[pix.PixelMessageType.iAmADie.index]?.remove('_init');
    }
  }

  @override
  GenericDType get dType {
    pix.PixelDieType dt = info?.pixelDieTypeFaces ?? pix.PixelDieType.unknown;

    return dt.toDType();
  }

  @override
  set dType(GenericDType faces) {
    throw UnsupportedError("pixel die can't change dTypes");
  }

  @override
  // TODO: implement blinkColor
  Color? get blinkColor => _blinkColor;

  @override
  set blinkColor(Color? c) {
    _blinkColor = c;
  }
}

class VirtualDie extends GenericDie {
  late final String _dieId;
  String? _name;
  final Random rand = Random();
  late GenericDType _dType;
  Color? _blinkColor;

  @override
  final GenericDieType type = GenericDieType.virtual;

  VirtualDie({required GenericDType dType, String? dieId, String? name}) {
    _dieId = dieId ?? Uuid().v4();
    _name = name;
    _dType = dType;
    setIndexValue(0);
  }

  @override
  String get dieId => _dieId;

  void setRollState(DiceRollState rs) {
    if ((rs == DiceRollState.rolled || rs == DiceRollState.onFace) && state.rollState == DiceRollState.rolling.index) {
      state.currentFaceIndex = rand.nextInt(_dType.faces);
      state.currentFaceValue = (state.currentFaceIndex! + _dType.indexOffset) * _dType.multiplier;
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

  void setIndexValue(int index) {
    state.currentFaceValue = (index + _dType.indexOffset) * _dType.multiplier;
    state.currentFaceIndex = index;
  }

  @override
  Future<void> _init() async {}

  @override
  String get friendlyName => (_name == null || _name!.isEmpty) ? "Virtual ${dType.name}" : _name!;

  @override
  set friendlyName(String name) {
    _name = name;
  }

  @override
  GenericDType get dType {
    return _dType;
  }

  @override
  set dType(GenericDType dType) {
    _dType = dType;
  }

  @override
  Color? get blinkColor => _blinkColor;

  @override
  set blinkColor(Color? c) {
    _blinkColor = c;
  }
}

class StaticVirtualDie extends GenericDie {
  late final String _dieId;
  String? _name;
  late GenericDType _dType;
  Color? _blinkColor;

  @override
  final GenericDieType type = GenericDieType.virtual;

  StaticVirtualDie({required GenericDType dType, required int index, String? dieId, String? name}) {
    _dieId = dieId ?? Uuid().v4();
    _name = name;
    _dType = dType;
    setIndexValue(index);
  }

  void setIndexValue(int index) {
    state.currentFaceValue = ((index + _dType.indexOffset) * _dType.multiplier).round();
    state.currentFaceIndex = index;
  }

  @override
  String get dieId => _dieId;

  @override
  Future<void> _init() async {}

  @override
  String get friendlyName => (_name == null || _name!.isEmpty) ? "Virtual ${dType.name}" : _name!;

  @override
  set friendlyName(String name) {
    _name = name;
  }

  @override
  GenericDType get dType {
    return _dType;
  }

  @override
  set dType(GenericDType dType) {
    _dType = dType;
  }

  @override
  Color? get blinkColor => _blinkColor;

  @override
  set blinkColor(Color? c) {
    _blinkColor = c;
  }
}
