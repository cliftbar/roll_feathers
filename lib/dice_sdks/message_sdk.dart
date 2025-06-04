
// Messages
import 'dart:ui';

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

abstract class Blinker extends TxMessage with Color255 {
  Blinker({required super.id});

  int getCount();

  Duration getOnDuration();

  Duration getOffDuration();
}

mixin Color255 {
  Color getColor();

  int r255() {
    return (getColor().r * getColor().a * 255).toInt();
  }

  int g255() {
    return (getColor().g * getColor().a * 255).toInt();
  }

  int b255() {
    return (getColor().b * getColor().a * 255).toInt();
  }

  int a255() {
    return (getColor().a * 255).toInt();
  }
}
