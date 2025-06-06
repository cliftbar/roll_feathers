import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../dice_sdks/dice_sdks.dart';
import 'message_sdk.dart';

String godiceServiceGuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
String godiceWriteCharacteristic = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
String godiceNotifyCharacteristic = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

// Die colors
enum GodiceDieColor { black, red, green, blue, yellow, orange, unknown }

class Vector {
  final int x;
  final int y;
  final int z;

  const Vector({required this.x, required this.y, required this.z});

  List<int> toJson() => [x, y, z];
}

// Die types
enum GodiceDieType {
  d6, // Regular 6-sided die
  d20, // 20-sided die
  d10, // 10-sided die
  d10X, // 10-sided percentile die (00-90)
  d4, // 4-sided die
  d8, // 8-sided die
  d12, // 12-sided die
  d24, // special form for vector transforms
}

const Map<GodiceDieType, Map<int, Vector>> vectors = {
  GodiceDieType.d6: {
    1: Vector(x: -64, y: 0, z: 0),
    2: Vector(x: 0, y: 0, z: 64),
    3: Vector(x: 0, y: 64, z: 0),
    4: Vector(x: 0, y: -64, z: 0),
    5: Vector(x: 0, y: 0, z: -64),
    6: Vector(x: 64, y: 0, z: 0),
  },
  GodiceDieType.d20: {
    1: Vector(x: -64, y: 0, z: -22),
    2: Vector(x: 42, y: -42, z: 40),
    3: Vector(x: 0, y: 22, z: -64),
    4: Vector(x: 0, y: 22, z: 64),
    5: Vector(x: -42, y: -42, z: 42),
    6: Vector(x: 22, y: 64, z: 0),
    7: Vector(x: -42, y: -42, z: -42),
    8: Vector(x: 64, y: 0, z: -22),
    9: Vector(x: -22, y: 64, z: 0),
    10: Vector(x: 42, y: -42, z: -42),
    11: Vector(x: -42, y: 42, z: 42),
    12: Vector(x: 22, y: -64, z: 0),
    13: Vector(x: -64, y: 0, z: 22),
    14: Vector(x: 42, y: 42, z: 42),
    15: Vector(x: -22, y: -64, z: 0),
    16: Vector(x: 42, y: 42, z: -42),
    17: Vector(x: 0, y: -22, z: -64),
    18: Vector(x: 0, y: -22, z: 64),
    19: Vector(x: -42, y: 42, z: -42),
    20: Vector(x: 64, y: 0, z: 22),
  },
  GodiceDieType.d24: {
    1: Vector(x: 20, y: -60, z: -20),
    2: Vector(x: 20, y: 0, z: 60),
    3: Vector(x: -40, y: -40, z: 40),
    4: Vector(x: -60, y: 0, z: 20),
    5: Vector(x: 40, y: 20, z: 40),
    6: Vector(x: -20, y: -60, z: -20),
    7: Vector(x: 20, y: 60, z: 20),
    8: Vector(x: -40, y: 20, z: -40),
    9: Vector(x: -40, y: 40, z: 40),
    10: Vector(x: -20, y: 0, z: 60),
    11: Vector(x: -20, y: -60, z: 20),
    12: Vector(x: 60, y: 0, z: 20),
    13: Vector(x: -60, y: 0, z: -20),
    14: Vector(x: 20, y: 60, z: -20),
    15: Vector(x: 20, y: 0, z: -60),
    16: Vector(x: 40, y: -20, z: -40),
    17: Vector(x: -20, y: 60, z: -20),
    18: Vector(x: -40, y: -40, z: -40),
    19: Vector(x: 40, y: -20, z: 40),
    20: Vector(x: 20, y: -60, z: 20),
    21: Vector(x: 60, y: 0, z: -20),
    22: Vector(x: 40, y: 20, z: -40),
    23: Vector(x: -20, y: 0, z: -60),
    24: Vector(x: -20, y: 60, z: 20),
  },
};

const Map<GodiceDieType, Map<int, int>> transforms = {
  GodiceDieType.d10: {
    1: 8,
    2: 2,
    3: 6,
    4: 1,
    5: 4,
    6: 3,
    7: 9,
    8: 0,
    9: 7,
    10: 5,
    11: 5,
    12: 7,
    13: 0,
    14: 9,
    15: 3,
    16: 4,
    17: 1,
    18: 6,
    19: 2,
    20: 8,
  },
  GodiceDieType.d10X: {
    1: 80,
    2: 20,
    3: 60,
    4: 10,
    5: 40,
    6: 30,
    7: 90,
    8: 0,
    9: 70,
    10: 50,
    11: 50,
    12: 70,
    13: 0,
    14: 90,
    15: 30,
    16: 40,
    17: 10,
    18: 60,
    19: 20,
    20: 80,
  },
  GodiceDieType.d4: {
    1: 3,
    2: 1,
    3: 4,
    4: 1,
    5: 4,
    6: 4,
    7: 1,
    8: 4,
    9: 2,
    10: 3,
    11: 1,
    12: 1,
    13: 1,
    14: 4,
    15: 2,
    16: 3,
    17: 3,
    18: 2,
    19: 2,
    20: 2,
    21: 4,
    22: 1,
    23: 3,
    24: 2,
  },
  GodiceDieType.d8: {
    1: 3,
    2: 3,
    3: 6,
    4: 1,
    5: 2,
    6: 8,
    7: 1,
    8: 1,
    9: 4,
    10: 7,
    11: 5,
    12: 5,
    13: 4,
    14: 4,
    15: 2,
    16: 5,
    17: 7,
    18: 7,
    19: 8,
    20: 2,
    21: 8,
    22: 3,
    23: 6,
    24: 6,
  },
  GodiceDieType.d12: {
    1: 1,
    2: 2,
    3: 3,
    4: 4,
    5: 5,
    6: 6,
    7: 7,
    8: 8,
    9: 9,
    10: 10,
    11: 11,
    12: 12,
    13: 1,
    14: 2,
    15: 3,
    16: 4,
    17: 5,
    18: 6,
    19: 7,
    20: 8,
    21: 9,
    22: 10,
    23: 11,
    24: 12,
  },
};

// Gets the xyz coord from sent message
Vector getXyzFromBytes(List<int> data, int startByte) {
  // values are int8's
  var int8Data = Int8List.fromList(data.sublist(startByte, startByte + 3));
  int x = int8Data[0];
  int y = int8Data[1];
  int z = int8Data[2];
  return Vector(x: x, y: y, z: z);
}

enum GodiceMessageType {
  unknown([0]),
  batteryLevel([3]),
  init([0x19]),
  updateSampleSettings([0x65]),
  diceColor([23]),
  setLed([8]),
  toggleLeds([16]),
  rollStart([82]), // "R"
  batteryLevelAck([66, 97, 116]), // "Bat"
  diceColorAck([67, 111, 108]), // "Col"
  stable([83]), // "S"
  fakeStable([70, 83]), // "FS
  tiltStable([84, 83]), // "TS"
  moveStable([77, 83]), // "MS"
  charging([67, 104, 97, 114]), // "Char"
  tap([84, 97, 112]), // "Tap"
  dTap([68, 84, 97, 112]) // "DTap"
  ;

  final List<int> value;

  const GodiceMessageType(this.value);

  static GodiceMessageType getByValue(int id) {
    return GodiceMessageType.values.firstWhere((v) => v.value[0] == id, orElse: () => unknown);
  }
}

class MessageBatteryLevel extends TxMessage {
  MessageBatteryLevel() : super(id: GodiceMessageType.batteryLevel.value[0]);

  @override
  List<int> toBuffer() {
    return GodiceMessageType.batteryLevel.value;
  }
}

class MessageDiceColor extends TxMessage {
  MessageDiceColor() : super(id: GodiceMessageType.diceColor.value[0]);

  @override
  List<int> toBuffer() {
    return GodiceMessageType.diceColor.value;
  }
}

enum BlinkMode { oneByOne, parallel }

enum BlinkLedSelector { both, ledOne, ledTwo }

class MessageInit extends TxMessage with Color255 {
  int diceSensitivity;
  int numberOfBlinks;
  int lightOnDuration10ms;
  int lightOffDuration10ms;
  Color connectColor;
  BlinkMode blinkMode;
  BlinkLedSelector leds;
  MessageInit({
    this.diceSensitivity = 30,
    this.numberOfBlinks = 1,
    this.lightOnDuration10ms = 50,
    this.lightOffDuration10ms = 50,
    this.connectColor = Colors.blue,
    this.blinkMode = BlinkMode.parallel,
    this.leds = BlinkLedSelector.both,
  }) : super(id: GodiceMessageType.init.value[0]);

  @override
  List<int> toBuffer() {
    return [
      id,
      diceSensitivity,
      numberOfBlinks,
      lightOnDuration10ms,
      lightOffDuration10ms,
      r255(),
      g255(),
      b255(),
      blinkMode.index,
      leds.index,
    ];
  }

  @override
  Color getColor() {
    return connectColor;
  }
}

class MessageToggleLeds extends Blinker with Color255 {
  int numberOfBlinks;
  int lightOnDuration10ms;
  int lightOffDuration10ms;
  Color toggleColor;
  BlinkMode blinkMode;
  BlinkLedSelector leds;
  MessageToggleLeds({
    this.numberOfBlinks = 2,
    this.lightOnDuration10ms = 25,
    this.lightOffDuration10ms = 25,
    this.toggleColor = Colors.white,
    this.blinkMode = BlinkMode.parallel,
    this.leds = BlinkLedSelector.both,
  }) : super(id: GodiceMessageType.toggleLeds.value[0]);

  @override
  List<int> toBuffer() {
    return [
      id,
      numberOfBlinks,
      lightOnDuration10ms,
      lightOffDuration10ms,
      r255(),
      g255(),
      b255(),
      blinkMode.index,
      leds.index,
    ];
  }

  @override
  Color getColor() {
    return toggleColor;
  }

  @override
  int getCount() {
    return numberOfBlinks;
  }

  @override
  Duration getOnDuration() {
    return Duration(milliseconds: lightOnDuration10ms * 10);
  }

  @override
  Duration getOffDuration() {
    return Duration(milliseconds: lightOffDuration10ms * 10);
  }
}

class MessageUpdateSampleSettings extends TxMessage {
  int samplesCount;
  int movementCount;
  int faceCount;
  int minFlatDeg;
  int maxFlatDeg;
  int weakStable;
  int movementDeg;
  int rollThreshold;
  MessageUpdateSampleSettings({
    this.samplesCount = 4,
    this.movementCount = 2,
    this.faceCount = 1,
    this.minFlatDeg = 10,
    this.maxFlatDeg = 54,
    this.weakStable = 20,
    this.movementDeg = 50,
    this.rollThreshold = 30,
  }) : super(id: GodiceMessageType.updateSampleSettings.value[0]);

  @override
  List<int> toBuffer() {
    return [id, samplesCount, movementCount, faceCount, minFlatDeg, maxFlatDeg, weakStable, movementDeg, rollThreshold];
  }
}

class MessageUnknown extends RxMessage {
  MessageUnknown({required super.buffer}) : super(id: GodiceMessageType.unknown.index);

  static MessageUnknown parse(List<int> data) {
    return MessageUnknown(buffer: data);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer};
  }
}

class MessageRollStart extends RxMessage {
  MessageRollStart({required super.buffer}) : super(id: GodiceMessageType.rollStart.index);

  static MessageRollStart parse(List<int> data) {
    return MessageRollStart(buffer: data);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer};
  }
}

class MessageBatteryLevelAck extends RxMessage {
  final int batteryLevel;
  MessageBatteryLevelAck({required super.buffer, required this.batteryLevel})
    : super(id: GodiceMessageType.batteryLevelAck.value[0]);

  static MessageBatteryLevelAck parse(List<int> data) {
    if (!ListEquality().equals(data.sublist(0, 3), GodiceMessageType.batteryLevelAck.value)) {
      throw MessageParseError("bad battery level message $data");
    }
    return MessageBatteryLevelAck(buffer: data, batteryLevel: data[3]);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'batteryLevel': batteryLevel};
  }
}

class MessageDiceColorAck extends RxMessage {
  final GodiceDieColor diceColor;
  MessageDiceColorAck({required super.buffer, required this.diceColor})
    : super(id: GodiceMessageType.batteryLevelAck.value[0]);

  static MessageDiceColorAck parse(List<int> data) {
    if (!ListEquality().equals(data.sublist(0, 3), GodiceMessageType.diceColorAck.value)) {
      throw MessageParseError("bad message $data");
    }
    GodiceDieColor color = GodiceDieColor.values[data[3]];
    return MessageDiceColorAck(buffer: data, diceColor: color);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'diceColor': diceColor.name};
  }
}

class MessageStable extends RxMessage {
  static final int _dataOffset = GodiceMessageType.stable.value.length;
  final Vector xyzData;
  MessageStable({required super.buffer, required this.xyzData}) : super(id: GodiceMessageType.stable.value[0]);

  static MessageStable parse(List<int> data) {
    if (!ListEquality().equals(data.sublist(0, _dataOffset), GodiceMessageType.stable.value)) {
      throw MessageParseError("bad stable message $data");
    }
    Vector xyzData = getXyzFromBytes(data, _dataOffset);

    return MessageStable(buffer: data, xyzData: xyzData);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'xyzData': xyzData.toJson()};
  }
}

class MessageFakeStable extends RxMessage {
  static final int _dataOffset = GodiceMessageType.fakeStable.value.length;
  final Vector xyzData;
  MessageFakeStable({required super.buffer, required this.xyzData}) : super(id: GodiceMessageType.fakeStable.value[0]);

  static MessageFakeStable parse(List<int> data) {
    if (!ListEquality().equals(data.sublist(0, _dataOffset), GodiceMessageType.fakeStable.value)) {
      throw MessageParseError("bad fake stable message $data");
    }
    Vector xyzData = getXyzFromBytes(data, _dataOffset);

    return MessageFakeStable(buffer: data, xyzData: xyzData);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'xyzData': xyzData.toJson()};
  }
}
