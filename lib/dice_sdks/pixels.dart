import 'package:flutter/material.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';

import '../util/color.dart';
import 'message_sdk.dart';

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
      currentFaceIndex: data[19],
      currentFaceValue: data[19] + 1,
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
