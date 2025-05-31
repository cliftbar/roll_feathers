import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'generic_die.dart';

const Color green = Color.fromARGB(255, 0, 255, 0);
const Color red = Color.fromARGB(255, 255, 0, 0);
const Color blue = Color.fromARGB(255, 0, 0, 255);

Guid pixelsService = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
const String information = "180a";
const String nordicsDFU = "fe59";
Guid pixelNotifyCharacteristic = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
Guid pixelWriteCharacteristic = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");

enum PixelDieType { unknown, d4, d6, d8, d10, d00, d12, d20, d6Pipped, d6Fudge }

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

enum PixelRollState { unknown, rolled, handling, rolling, crooked, onFace }

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
  final int designAndColor;
  final int reserved;
  final int dataSetHash;
  final int pixelId;
  final int availableFlash;
  final int buildTimestamp;

  PixelDiceInfo({
    required this.ledCount,
    required this.designAndColor,
    required this.reserved,
    required this.dataSetHash,
    required this.pixelId,
    required this.availableFlash,
    required this.buildTimestamp,
  });

  factory PixelDiceInfo.fromJson(Map<String, dynamic> json) {
    return PixelDiceInfo(
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
  final int designAndColor;
  final int reserved;
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
    required this.reserved,
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
      designAndColor: data[2],
      reserved: data[3],
      dataSetHash: Message.bytesToIntList(data.sublist(4, 8)),
      pixelId: Message.bytesToIntList(data.sublist(8, 12)),
      availableFlash: Message.bytesToIntList(data.sublist(12, 14)),
      buildTimestamp: Message.bytesToIntList(data.sublist(14, 18)),
      rollState: data[18],
      currentFaceIndex: data[19],
      currentFaceValue: data[19] + 1,
      batteryLevel: data[20],
      batteryState: data[21],
    );
  }

  factory MessageIAmADie.fromJson(Map<String, dynamic> json) {
    return MessageIAmADie(
      buffer: json['buffer'],
      ledCount: json['ledCount'] as int,
      designAndColor: json['designAndColor'] as int,
      reserved: json['reserved'] as int,
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
      'designAndColor': designAndColor,
      'reserved': reserved,
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

class BlinkMessage extends TxMessage with Color255 implements Blinker {
  final int count;
  final int duration;
  final Color blinkColor;
  final int faceMask;
  final int fade;
  final int loopCount;

  BlinkMessage({
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
  int getDuration() {
    return duration;
  }

  @override
  int getLoopCount() {
    return loopCount;
  }
}