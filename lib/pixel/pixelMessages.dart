
import 'package:color/color.dart';

import 'package:roll_feathers/pixel/pixelConstants.dart';

abstract class Message {
  final int id;

  Message({required this.id});

  static int _bytesToInt(List<int> bytes) {
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

class MessageWhoAreYou extends TxMessage {

  MessageWhoAreYou() : super(id: MessageType.whoAreYou.index);

  @override
  List<int> toBuffer() {
    return [MessageType.whoAreYou.index];
  }
}

class MessageBatteryLevel extends RxMessage {
  final int batteryLevel;
  final int batteryState;

  MessageBatteryLevel({
    required super.buffer,
    required this.batteryLevel,
    required this.batteryState,
  }) : super(id: MessageType.batteryLevel.index);

  static MessageBatteryLevel parse(List<int> data) {
    return MessageBatteryLevel(
      buffer: data,
      batteryLevel: data[1],
      batteryState: data[2],
    );
  }

  factory MessageBatteryLevel.fromJson(Map<String, dynamic> json) {
    return MessageBatteryLevel(
      buffer: json['buffer'],
      batteryLevel: json['batteryLevel'] as int,
      batteryState: json['batteryState'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'buffer': buffer,
      'batteryLevel': batteryLevel,
      'batteryState': batteryState,
    };
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
  }) : super(id: MessageType.rollState.index);

  static MessageRollState parse(List<int> data) {
    return MessageRollState(
      buffer: data,
      rollState: data[1],
      currentFaceIndex: data[2],
      currentFaceValue: data[2] + 1,
    );
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
  }) : super(id: MessageType.iAmADie.index);

  static MessageIAmADie parse(List<int> data) {
    return MessageIAmADie(
      buffer: data,
      ledCount: data[1],
      designAndColor: data[2],
      reserved: data[3],
      dataSetHash: Message._bytesToInt(data.sublist(4, 8)),
      pixelId: Message._bytesToInt(data.sublist(8, 12)),
      availableFlash: Message._bytesToInt(data.sublist(12, 14)),
      buildTimestamp: Message._bytesToInt(data.sublist(14, 18)),
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

  MessageNone({
    required super.buffer,
  }) : super(id: MessageType.iAmADie.index);

  static MessageNone parse(List<int> data) {
    return MessageNone(
      buffer: data,
    );
  }

  factory MessageNone.fromJson(Map<String, dynamic> json) {
    return MessageNone(
      buffer: json['buffer'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'buffer': buffer,
    };
  }
}

abstract class Blinker {
  int getCount();
  int getDuration();
  Color getBlinkColor();
  int getLoopCount();
}

class BlinkMessage extends TxMessage implements Blinker {
  final int count;
  final int duration;
  final Color blinkColor;
  final int faceMask;
  final int fade;
  final int loopCount;

  BlinkMessage({
    this.count = 1,
    this.duration = 500,
    this.blinkColor = const Color.rgb(255, 255, 255),
    this.faceMask = 0xFFFFFFFF,
    this.fade = 0,
    this.loopCount = 2,
  }) : super(id: MessageType.blink.index);

  @override
  List<int> toBuffer() {
    var buffer = List<int>.filled(14, 0);
    buffer[0] = MessageType.blink.index;
    buffer[1] = count;
    buffer[2] = duration & 0xFF;
    buffer[3] = (duration >> 8) & 0xFF;
    buffer[4] = blinkColor.toRgbColor().b.toInt();
    buffer[5] = blinkColor.toRgbColor().g.toInt();
    buffer[6] = blinkColor.toRgbColor().r.toInt();
    buffer[7] = 255;
    buffer[8] = faceMask & 0xFF;
    buffer[9] = (faceMask >> 8) & 0xFF;
    buffer[10] = (faceMask >> 16) & 0xFF;
    buffer[11] = (faceMask >> 24) & 0xFF;
    buffer[12] = fade;
    buffer[13] = loopCount;
    return buffer;
  }

  @override
  Color getBlinkColor() {
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

