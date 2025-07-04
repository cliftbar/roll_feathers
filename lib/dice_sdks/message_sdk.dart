// Messages
import 'dart:ui';

import '../util/color.dart';

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
