// Messages
import 'dart:ui';

import 'package:roll_feathers/util/color.dart';

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

  /// Writes [value] as a little-endian uint16 into [buf] at [offset].
  static void setU16(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
  }

  /// Writes [value] as a little-endian uint32 into [buf] at [offset].
  static void setU32(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
  }
}

abstract class Blinker with Color255 {
  int getCount();

  Duration getOnDuration();

  Duration getOffDuration();
}

class BasicBlinker with Color255 implements Blinker {
  final int _count;
  final Duration _onDuration;
  final Duration _offDuration;
  final Color _color;

  BasicBlinker(this._count, this._onDuration, this._offDuration, this._color);

  @override
  int getCount() => _count;

  @override
  Duration getOnDuration() => _onDuration;

  @override
  Duration getOffDuration() => _offDuration;

  @override
  Color getColor() => _color;
}
