// GoDice service and characteristic UUIDs
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:roll_feathers/dice_sdks/generic_die.dart';
import 'package:collection/collection.dart';


Guid godiceServiceGuid = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
Guid godiceWriteCharacteristic = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
Guid godiceNotifyCharacteristic = Guid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");

// Die colors
enum GodiceDieColor {
  black,
  red,
  green,
  blue,
  yellow,
  orange,
  unknown
}

class Vector {
  final int x;
  final int y;
  final int z;

  const Vector({required this.x, required this.y, required this.z});
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

enum GodiceMessageType {
  unknown([0]),
  batteryLevel([3]),
  diceColor([23]),
  setLed([8]),
  setLedToggle([16]),
  rollStart([82]),
  batteryLevelAck([66, 97, 116]),
  diceColorAck([67, 111, 108]),
  stable([83]),
  fakeStable([70, 83]),
  tiltStable([84, 83]),
  moveStable([77, 83])
  ;

  final List<int> value;

  const GodiceMessageType(this.value);

  static GodiceMessageType getByValue(int id) {
    return GodiceMessageType.values.firstWhere((v) => v.value[0] == id, orElse: () => unknown);
  }
}

class MessageUnknown extends RxMessage {
  MessageUnknown({required super.buffer}) : super(id: GodiceMessageType.unknown.index);

  static MessageUnknown parse(List<int> data) {
    return MessageUnknown(buffer: data);
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

class MessageBatteryLevelAck extends RxMessage {
  final int batteryLevel;
  MessageBatteryLevelAck({required super.buffer, required this.batteryLevel}) : super(id: GodiceMessageType.batteryLevelAck.value[0]);

  static MessageBatteryLevelAck parse(List<int> data) {
    if (!ListEquality().equals(data.sublist(0, 3), GodiceMessageType.batteryLevelAck.value)) {
      throw Exception("bad message");
    }
    return MessageBatteryLevelAck(buffer: data, batteryLevel: data[3]);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'batteryLevel': batteryLevel};
  }
}

class MessageDiceColorAck extends RxMessage {
  final GodiceDieColor diceColor;
  MessageDiceColorAck({required super.buffer, required this.diceColor}) : super(id: GodiceMessageType.batteryLevelAck.value[0]);

  static MessageDiceColorAck parse(List<int> data) {
    if (!ListEquality().equals(data.sublist(0, 3), GodiceMessageType.diceColorAck.value)) {
      throw Exception("bad message $data");
    }
    GodiceDieColor color = GodiceDieColor.values[data[3]];
    return MessageDiceColorAck(buffer: data, diceColor: color);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'buffer': buffer, 'diceColor': diceColor.name};
  }
}