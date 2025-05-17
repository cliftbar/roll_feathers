import 'package:flutter_blue_plus/flutter_blue_plus.dart';

Guid pixelsService = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
const String information = "180a";
const String nordicsDFU = "fe59";
Guid pixelNotifyCharacteristic = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
Guid pixelWriteCharacteristic = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");

enum DieType { unknown, d4, d6, d8, d10, d00, d12, d20, d6Pipped, d6Fudge }

enum DesignAndColor {
  unknown(0),
  onyxBlack(1),
  hematiteGrey(2),
  midnightGalaxy(3),
  auroraSky(4),
  clear(5),
  whiteAurora(6),
  custom(255);

  final int value;

  const DesignAndColor(this.value);
}

enum RollState { unknown, rolled, handling, rolling, crooked, onFace }

enum BatteryState { unknown, ok, low, transition, badCharging, error, charging, trickleCharge, done, lowTemp, highTemp }

enum MessageType {
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
