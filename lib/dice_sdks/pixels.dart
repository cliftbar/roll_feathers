import 'package:flutter/material.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';

import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/util/color.dart';

const Color green = Color.fromARGB(255, 0, 255, 0);
const Color red = Color.fromARGB(255, 255, 0, 0);
const Color blue = Color.fromARGB(255, 0, 0, 255);

const String pixelsService = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String information = "180a";
const String nordicsDFU = "fe59";
const String pixelNotifyCharacteristic = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String pixelWriteCharacteristic = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

enum PixelDieType {
  unknown(-1),
  d4(4),
  d6(6),
  d8(8),
  d10(10),
  d00(10),
  d12(12),
  d20(20),
  d6Pipped(6),
  d6Fudge(6);

  final int faces;

  const PixelDieType(this.faces);

  GenericDType toDType() {
    switch (this) {
      case PixelDieType.unknown:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.unknown);
      case PixelDieType.d4:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d4);
      case PixelDieType.d6:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6);
      case PixelDieType.d8:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d8);
      case PixelDieType.d10:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d10);
      case PixelDieType.d00:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d00);
      case PixelDieType.d12:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d12);
      case PixelDieType.d20:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d20);
      case PixelDieType.d6Pipped:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6);
      case PixelDieType.d6Fudge:
        return GenericDTypeFactory.getKnownChecked(GenericDTypeFactory.d6);
    }
  }
}

enum PixelDesignAndColor {
  unknown(0),
  onyxBlack(1),
  hematiteGrey(2),
  midnightGalaxy(3),
  auroraSky(4),
  clear(5),
  whiteAurora(6),
  custom(255);

  final int value;

  const PixelDesignAndColor(this.value);
}

enum PixelMessageType {
  none,
  whoAreYou,
  iAmADie,
  rollState,
  telemetry,
  bulkSetup,
  bulkSetupAck,
  bulkData,
  bulkDataAck,
  transferAnimationSet,
  transferAnimationSetAck,
  transferAnimationSetFinished,
  transferSettings,
  transferSettingsAck,
  transferSettingsFinished,
  transferTestAnimationSet,
  transferTestAnimationSetAck,
  transferTestAnimationSetFinished,
  debugLog,
  playAnimation,
  playAnimationEvent,
  stopAnimation,
  remoteAction,
  requestRollState,
  requestAnimationSet,
  requestSettings,
  requestTelemetry,
  programDefaultAnimationSet,
  programDefaultAnimationSetFinished,
  blink,
  blinkAck,
  requestDefaultAnimationSetColor,
  defaultAnimationSetColor,
  requestBatteryLevel,
  batteryLevel,
  requestRssi,
  rssi,
  calibrate,
  calibrateFace,
  notifyUser,
  notifyUserAck,
  testHardware,
  testLEDLoopback,
  ledLoopback,
  setTopLevelState,
  programDefaultParameters,
  programDefaultParametersFinished,
  setDesignAndColor,
  setDesignAndColorAck,
  setCurrentBehavior,
  setCurrentBehaviorAck,
  setName,
  setNameAck,
  sleep,
  exitValidation,
  transferInstantAnimationSet,
  transferInstantAnimationSetAck,
  transferInstantAnimationSetFinished,
  playInstantAnimation,
  stopAllAnimations,
  requestTemperature,
  temperature,
  enableCharging,
  disableCharging,
  discharge,
}

class PixelDiceInfo {
  final int ledCount;
  final PixelDesignAndColor designAndColor;
  final PixelDieType pixelDieTypeFaces;
  final int dataSetHash;
  final int pixelId;
  final int availableFlash;
  final int buildTimestamp;

  PixelDiceInfo({
    required this.ledCount,
    required this.designAndColor,
    required this.pixelDieTypeFaces,
    required this.dataSetHash,
    required this.pixelId,
    required this.availableFlash,
    required this.buildTimestamp,
  });

  factory PixelDiceInfo.fromJson(Map<String, dynamic> json) {
    return PixelDiceInfo(
      ledCount: json['ledCount'] as int,
      designAndColor: PixelDesignAndColor.values[json['designAndColor'] as int],
      pixelDieTypeFaces: PixelDieType.values[json['reserved'] as int],
      dataSetHash: json['dataSetHash'] as int,
      pixelId: json['pixelId'] as int,
      availableFlash: json['availableFlash'] as int,
      buildTimestamp: json['buildTimestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ledCount': ledCount,
      'designAndColor': designAndColor.index,
      'reserved': pixelDieTypeFaces.index,
      'dataSetHash': dataSetHash,
      'pixelId': pixelId,
      'availableFlash': availableFlash,
      'buildTimestamp': buildTimestamp,
    };
  }
}

// Messages

class MessageWhoAreYou extends TxMessage {
  MessageWhoAreYou() : super(id: PixelMessageType.whoAreYou.index);

  @override
  List<int> toBuffer() {
    return [PixelMessageType.whoAreYou.index];
  }
}

class MessageBatteryLevel extends RxMessage {
  final int batteryLevel;
  final int batteryState;

  MessageBatteryLevel({required super.buffer, required this.batteryLevel, required this.batteryState})
    : super(id: PixelMessageType.batteryLevel.index);

  static MessageBatteryLevel parse(List<int> data) {
    return MessageBatteryLevel(buffer: data, batteryLevel: data[1], batteryState: data[2]);
  }

  factory MessageBatteryLevel.fromJson(Map<String, dynamic> json) {
    return MessageBatteryLevel(
      buffer: json['buffer'],
      batteryLevel: json['batteryLevel'] as int,
      batteryState: json['batteryState'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'batteryLevel': batteryLevel, 'batteryState': batteryState};
  }
}

class MessageRollState extends RxMessage {
  final int rollState;
  final int currentFaceIndex;
  final int currentFaceValue;

  MessageRollState({
    required super.buffer,
    required this.rollState,
    required this.currentFaceIndex,
    required this.currentFaceValue,
  }) : super(id: PixelMessageType.rollState.index);

  static MessageRollState parse(List<int> data) {
    return MessageRollState(buffer: data, rollState: data[1], currentFaceIndex: data[2], currentFaceValue: data[2] + 1);
  }

  factory MessageRollState.fromJson(Map<String, dynamic> json) {
    return MessageRollState(
      buffer: json['buffer'],
      rollState: json['rollState'] as int,
      currentFaceIndex: json['currentFaceIndex'] as int,
      currentFaceValue: json['currentFaceValue'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'buffer': buffer,
      'rollState': rollState,
      'currentFaceIndex': currentFaceIndex,
      'currentFaceValue': currentFaceValue,
    };
  }
}

class MessageIAmADie extends RxMessage {
  final int ledCount;
  final PixelDesignAndColor designAndColor;
  final PixelDieType pixelDieTypeFaces;
  final int dataSetHash;
  final int pixelId;
  final int availableFlash;
  final int buildTimestamp;
  final int rollState;
  final int currentFaceIndex;
  final int currentFaceValue;
  final int batteryLevel;
  final int batteryState;

  MessageIAmADie({
    required super.buffer,
    required this.ledCount,
    required this.designAndColor,
    required this.pixelDieTypeFaces,
    required this.dataSetHash,
    required this.pixelId,
    required this.availableFlash,
    required this.buildTimestamp,
    required this.rollState,
    required this.currentFaceIndex,
    required this.currentFaceValue,
    required this.batteryLevel,
    required this.batteryState,
  }) : super(id: PixelMessageType.iAmADie.index);

  static MessageIAmADie parse(List<int> data) {
    return MessageIAmADie(
      buffer: data,
      ledCount: data[1],
      designAndColor: PixelDesignAndColor.values[data[2]],
      pixelDieTypeFaces: PixelDieType.values[data[3]],
      dataSetHash: Message.bytesToIntList(data.sublist(4, 8)),
      pixelId: Message.bytesToIntList(data.sublist(8, 12)),
      availableFlash: Message.bytesToIntList(data.sublist(12, 14)),
      buildTimestamp: Message.bytesToIntList(data.sublist(14, 18)),
      rollState: data[18],
      currentFaceIndex: data.length > 19 ? data[19] : 0,
      currentFaceValue: data.length > 19 ? data[19] + 1 : 0,
      batteryLevel: data.length >= 21 ? data[20] : 0,
      batteryState: data.length >= 22 ? data[21] : BatteryState.unknown.index,
    );
  }

  factory MessageIAmADie.fromJson(Map<String, dynamic> json) {
    return MessageIAmADie(
      buffer: json['buffer'],
      ledCount: json['ledCount'] as int,
      designAndColor: PixelDesignAndColor.values[json['designAndColor'] as int],
      pixelDieTypeFaces: PixelDieType.values[json['reserved'] as int],
      dataSetHash: json['dataSetHash'] as int,
      pixelId: json['pixelId'] as int,
      availableFlash: json['availableFlash'] as int,
      buildTimestamp: json['buildTimestamp'] as int,
      rollState: json['rollState'] as int,
      currentFaceIndex: json['currentFaceIndex'] as int,
      currentFaceValue: json['currentFaceValue'] as int,
      batteryLevel: json['batteryLevel'] as int,
      batteryState: json['batteryState'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'buffer': buffer,
      'ledCount': ledCount,
      'designAndColor': designAndColor.index,
      'reserved': pixelDieTypeFaces.index,
      'dataSetHash': dataSetHash,
      'pixelId': pixelId,
      'availableFlash': availableFlash,
      'buildTimestamp': buildTimestamp,
      'rollState': rollState,
      'currentFaceIndex': currentFaceIndex,
      'currentFaceValue': currentFaceValue,
      'batteryLevel': batteryLevel,
      'batteryState': batteryState,
    };
  }
}

class MessageNone extends RxMessage {
  MessageNone({required super.buffer}) : super(id: PixelMessageType.none.index);

  static MessageNone parse(List<int> data) {
    return MessageNone(buffer: data);
  }

  factory MessageNone.fromJson(Map<String, dynamic> json) {
    return MessageNone(buffer: json['buffer']);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer};
  }
}

class MessageBlink extends TxMessage with Color255 implements Blinker {
  final int count;
  final int duration;
  final Color blinkColor;
  final int faceMask;
  final int fade;
  final int loopCount;

  MessageBlink({
    this.count = 1,
    this.duration = 500,
    this.blinkColor = Colors.white,
    this.faceMask = 0xFFFFFFFF,
    this.fade = 0,
    this.loopCount = 2,
  }) : super(id: PixelMessageType.blink.index);

  @override
  List<int> toBuffer() {
    var buffer = List<int>.filled(14, 0);
    buffer[0] = PixelMessageType.blink.index;
    buffer[1] = count;
    buffer[2] = duration & 0xFF;
    buffer[3] = (duration >> 8) & 0xFF;
    buffer[4] = b255();
    buffer[5] = g255();
    buffer[6] = r255();
    buffer[7] = a255();
    buffer[8] = faceMask & 0xFF;
    buffer[9] = (faceMask >> 8) & 0xFF;
    buffer[10] = (faceMask >> 16) & 0xFF;
    buffer[11] = (faceMask >> 24) & 0xFF;
    buffer[12] = fade;
    buffer[13] = loopCount;
    return buffer;
  }

  @override
  Color getColor() {
    return blinkColor;
  }

  @override
  int getCount() {
    return count;
  }

  @override
  Duration getOnDuration() {
    return Duration(milliseconds: duration);
  }

  @override
  Duration getOffDuration() {
    return Duration(milliseconds: duration);
  }
}

/// Stops all currently playing animations on the die.
class MessageStopAllAnimations extends TxMessage {
  MessageStopAllAnimations() : super(id: PixelMessageType.stopAllAnimations.index);

  @override
  List<int> toBuffer() => [PixelMessageType.stopAllAnimations.index];
}

/// Rename the die (max 31 chars + null terminator = 32 bytes payload).
class MessageSetName extends TxMessage {
  static const int maxNameBytes = 31;
  final String name;

  MessageSetName(this.name) : super(id: PixelMessageType.setName.index);

  @override
  List<int> toBuffer() {
    final encoded = name.codeUnits.take(maxNameBytes).toList();
    final buf = List<int>.filled(1 + maxNameBytes + 1, 0);
    buf[0] = PixelMessageType.setName.index;
    for (var i = 0; i < encoded.length; i++) {
      buf[1 + i] = encoded[i];
    }
    return buf;
  }
}

/// Request the die to identify itself (re-send iAmADie).
class MessageRequestRollState extends TxMessage {
  MessageRequestRollState() : super(id: PixelMessageType.requestRollState.index);

  @override
  List<int> toBuffer() => [PixelMessageType.requestRollState.index];
}

/// Request the die to send back its animation set.
class MessageRequestAnimationSet extends TxMessage {
  MessageRequestAnimationSet() : super(id: PixelMessageType.requestAnimationSet.index);

  @override
  List<int> toBuffer() => [PixelMessageType.requestAnimationSet.index];
}

// ─── Bulk transfer messages ───────────────────────────────────────────────────

/// Step 1 of a profile upload: tell the die the total byte size.
class MessageTransferAnimationSet extends TxMessage {
  final int paletteSize;
  final int rgbKeyFrameCount;
  final int rgbTrackCount;
  final int keyFrameCount;
  final int trackCount;
  final int animationCount;
  final int animationSize;
  final int conditionCount;
  final int conditionSize;
  final int actionCount;
  final int actionSize;
  final int ruleCount;
  final int brightness;

  MessageTransferAnimationSet({
    required this.paletteSize,
    required this.rgbKeyFrameCount,
    required this.rgbTrackCount,
    required this.keyFrameCount,
    required this.trackCount,
    required this.animationCount,
    required this.animationSize,
    required this.conditionCount,
    required this.conditionSize,
    required this.actionCount,
    required this.actionSize,
    required this.ruleCount,
    required this.brightness,
  }) : super(id: PixelMessageType.transferAnimationSet.index);

  @override
  List<int> toBuffer() {
    final buf = List<int>.filled(26, 0);
    buf[0] = PixelMessageType.transferAnimationSet.index;
    _setU16(buf, 1, paletteSize);
    _setU16(buf, 3, rgbKeyFrameCount);
    _setU16(buf, 5, rgbTrackCount);
    _setU16(buf, 7, keyFrameCount);
    _setU16(buf, 9, trackCount);
    _setU16(buf, 11, animationCount);
    _setU16(buf, 13, animationSize);
    _setU16(buf, 15, conditionCount);
    _setU16(buf, 17, conditionSize);
    _setU16(buf, 19, actionCount);
    _setU16(buf, 21, actionSize);
    _setU16(buf, 23, ruleCount);
    buf[25] = brightness;
    return buf;
  }

  static void _setU16(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
  }
}

/// Die response to TransferAnimationSet: result=0 → proceed, else no memory.
class MessageTransferAnimationSetAck extends RxMessage {
  final int result;

  MessageTransferAnimationSetAck({required super.buffer, required this.result})
      : super(id: PixelMessageType.transferAnimationSetAck.index);

  static MessageTransferAnimationSetAck parse(List<int> data) =>
      MessageTransferAnimationSetAck(buffer: data, result: data.length > 1 ? data[1] : 0);

  bool get canDownload => result == 0;
}

/// Die signals profile was written to flash.
class MessageTransferAnimationSetFinished extends RxMessage {
  MessageTransferAnimationSetFinished({required super.buffer})
      : super(id: PixelMessageType.transferAnimationSetFinished.index);

  static MessageTransferAnimationSetFinished parse(List<int> data) =>
      MessageTransferAnimationSetFinished(buffer: data);
}

/// Step 1 of a bulk data transfer: tell the die the total byte size.
class MessageBulkSetup extends TxMessage {
  final int size;

  MessageBulkSetup({required this.size}) : super(id: PixelMessageType.bulkSetup.index);

  @override
  List<int> toBuffer() {
    final buf = List<int>.filled(3, 0);
    buf[0] = PixelMessageType.bulkSetup.index;
    buf[1] = size & 0xFF;
    buf[2] = (size >> 8) & 0xFF;
    return buf;
  }
}

/// Die acknowledges BulkSetup — ready for data.
class MessageBulkSetupAck extends RxMessage {
  MessageBulkSetupAck({required super.buffer})
      : super(id: PixelMessageType.bulkSetupAck.index);

  static MessageBulkSetupAck parse(List<int> data) =>
      MessageBulkSetupAck(buffer: data);
}

/// Bulk data chunk (up to 100 bytes payload).
class MessageBulkData extends TxMessage {
  final int size;
  final int offset;
  final List<int> data;

  MessageBulkData({required this.size, required this.offset, required this.data})
      : super(id: PixelMessageType.bulkData.index);

  @override
  List<int> toBuffer() {
    final buf = List<int>.filled(4 + data.length, 0);
    buf[0] = PixelMessageType.bulkData.index;
    buf[1] = size;
    buf[2] = offset & 0xFF;
    buf[3] = (offset >> 8) & 0xFF;
    for (var i = 0; i < data.length; i++) {
      buf[4 + i] = data[i];
    }
    return buf;
  }
}

/// Die acknowledges a BulkData chunk — contains the next expected offset.
class MessageBulkDataAck extends RxMessage {
  final int offset;

  MessageBulkDataAck({required super.buffer, required this.offset})
      : super(id: PixelMessageType.bulkDataAck.index);

  static MessageBulkDataAck parse(List<int> data) => MessageBulkDataAck(
    buffer: data,
    offset: data.length >= 3 ? (data[1] | (data[2] << 8)) : 0,
  );
}

// ─── Instant animation transfer ──────────────────────────────────────────────

/// Upload animation set to RAM (temporary; lost on sleep/reboot).
class MessageTransferInstantAnimationSet extends TxMessage {
  final int paletteSize;
  final int rgbKeyFrameCount;
  final int rgbTrackCount;
  final int keyFrameCount;
  final int trackCount;
  final int animationCount;
  final int animationSize;
  final int hash;

  MessageTransferInstantAnimationSet({
    required this.paletteSize,
    required this.rgbKeyFrameCount,
    required this.rgbTrackCount,
    required this.keyFrameCount,
    required this.trackCount,
    required this.animationCount,
    required this.animationSize,
    required this.hash,
  }) : super(id: PixelMessageType.transferInstantAnimationSet.index);

  @override
  List<int> toBuffer() {
    final buf = List<int>.filled(22, 0);
    buf[0] = PixelMessageType.transferInstantAnimationSet.index;
    _setU16(buf, 1, paletteSize);
    _setU16(buf, 3, rgbKeyFrameCount);
    _setU16(buf, 5, rgbTrackCount);
    _setU16(buf, 7, keyFrameCount);
    _setU16(buf, 9, trackCount);
    _setU16(buf, 11, animationCount);
    _setU16(buf, 13, animationSize);
    _setU32(buf, 15, hash);
    return buf;
  }

  static void _setU16(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
  }

  static void _setU32(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
  }
}

/// Ack values for TransferInstantAnimationSet.
enum TransferInstantAckType { download, upToDate, noMemory }

/// Die response to TransferInstantAnimationSet.
class MessageTransferInstantAnimationSetAck extends RxMessage {
  final TransferInstantAckType ackType;

  MessageTransferInstantAnimationSetAck({required super.buffer, required this.ackType})
      : super(id: PixelMessageType.transferInstantAnimationSetAck.index);

  static MessageTransferInstantAnimationSetAck parse(List<int> data) {
    final raw = data.length > 1 ? data[1] : 0;
    final ackType = raw < TransferInstantAckType.values.length
        ? TransferInstantAckType.values[raw]
        : TransferInstantAckType.noMemory;
    return MessageTransferInstantAnimationSetAck(buffer: data, ackType: ackType);
  }
}

/// Die signals instant animations are loaded.
class MessageTransferInstantAnimationSetFinished extends RxMessage {
  MessageTransferInstantAnimationSetFinished({required super.buffer})
      : super(id: PixelMessageType.transferInstantAnimationSetFinished.index);

  static MessageTransferInstantAnimationSetFinished parse(List<int> data) =>
      MessageTransferInstantAnimationSetFinished(buffer: data);
}

/// Play a previously uploaded instant animation.
class MessagePlayInstantAnimation extends TxMessage {
  final int animIndex;
  final int faceIndex;
  final int loopCount;

  MessagePlayInstantAnimation({
    this.animIndex = 0,
    this.faceIndex = 0,
    this.loopCount = 1,
  }) : super(id: PixelMessageType.playInstantAnimation.index);

  @override
  List<int> toBuffer() => [
    PixelMessageType.playInstantAnimation.index,
    animIndex,
    faceIndex,
    loopCount,
  ];
}

/// Die sends this when a behavior rule with Action_RunOnDevice fires.
class MessageRemoteAction extends RxMessage {
  final int actionId;

  MessageRemoteAction({required super.buffer, required this.actionId})
      : super(id: PixelMessageType.remoteAction.index);

  static MessageRemoteAction parse(List<int> data) => MessageRemoteAction(
    buffer: data,
    actionId: data.length >= 3 ? (data[1] | (data[2] << 8)) : 0,
  );
}

/// Die sends this for user notifications (toast/dialog on app).
class MessageNotifyUser extends RxMessage {
  final int timeoutSec;
  final bool ok;
  final bool cancel;
  final String message;

  MessageNotifyUser({
    required super.buffer,
    required this.timeoutSec,
    required this.ok,
    required this.cancel,
    required this.message,
  }) : super(id: PixelMessageType.notifyUser.index);

  static MessageNotifyUser parse(List<int> data) {
    final msgBytes = data.length > 4 ? data.sublist(4) : <int>[];
    final nullIdx = msgBytes.indexOf(0);
    final msg = String.fromCharCodes(nullIdx >= 0 ? msgBytes.sublist(0, nullIdx) : msgBytes);
    return MessageNotifyUser(
      buffer: data,
      timeoutSec: data.length > 1 ? data[1] : 0,
      ok: data.length > 2 && data[2] != 0,
      cancel: data.length > 3 && data[3] != 0,
      message: msg,
    );
  }
}

/// App sends this to acknowledge a NotifyUser message.
class MessageNotifyUserAck extends TxMessage {
  final bool okCancel;

  MessageNotifyUserAck({required this.okCancel})
      : super(id: PixelMessageType.notifyUserAck.index);

  @override
  List<int> toBuffer() => [PixelMessageType.notifyUserAck.index, okCancel ? 1 : 0];
}
