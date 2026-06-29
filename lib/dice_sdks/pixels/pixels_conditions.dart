part of 'pixels_animation.dart';

// ─────────────────────────────────────────────────────────────
// Conditions
// ─────────────────────────────────────────────────────────────

enum PixelConditionType { none, helloGoodbye, handling, rolling, faceCompare, crooked, connection, battery, idle, rolled }

// Condition flag bits (PixelBatteryFlags / PixelHelloFlags / PixelConnectionFlags)
// live in pixels_constants.dart, available here via the library import.

abstract class PixelCondition {
  PixelConditionType get type;
  int get byteSize;
  void writeTo(ByteData data, int offset);
  Map<String, dynamic> toJson();
  String get displayName;

  static PixelCondition fromJson(Map<String, dynamic> json) {
    final t = PixelConditionType.values.byName(json['type'] as String);
    return switch (t) {
      PixelConditionType.rolled => PixelConditionRolled.fromJson(json),
      PixelConditionType.rolling => PixelConditionRolling.fromJson(json),
      PixelConditionType.helloGoodbye => PixelConditionHelloGoodbye.fromJson(json),
      PixelConditionType.handling => PixelConditionHandling(),
      PixelConditionType.crooked => PixelConditionCrooked(),
      PixelConditionType.connection => PixelConditionConnectionState.fromJson(json),
      PixelConditionType.battery => PixelConditionBatteryState.fromJson(json),
      PixelConditionType.idle => PixelConditionIdle.fromJson(json),
      _ => throw UnsupportedError('Unsupported condition type: $t'),
    };
  }
}

/// Triggers when the die lands on one of the specified faces (type=9, 8 bytes).
class PixelConditionRolled extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.rolled;

  /// Bit N = face index N triggers. Set kFaceMaskAll for any face.
  int faceMask;

  PixelConditionRolled({this.faceMask = kFaceMaskAll});

  @override
  int get byteSize => 8;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.rolled.index);
    data.setUint8(offset + 1, 0);
    data.setUint8(offset + 2, 0);
    data.setUint8(offset + 3, 0);
    data.setUint32(offset + 4, faceMask, Endian.little);
  }

  @override
  String get displayName => 'Rolled';

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'faceMask': faceMask};

  factory PixelConditionRolled.fromJson(Map<String, dynamic> json) =>
      PixelConditionRolled(faceMask: (json['faceMask'] as int?) ?? kFaceMaskAll);
}

/// Triggers while the die is being shaken/rolled (type=3, 4 bytes).
class PixelConditionRolling extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.rolling;

  /// 0 = fire once, >0 = repeat every N ms.
  int repeatPeriodMs;

  PixelConditionRolling({this.repeatPeriodMs = 0});

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.rolling.index);
    data.setUint8(offset + 1, 0);
    data.setUint16(offset + 2, repeatPeriodMs, Endian.little);
  }

  @override
  String get displayName => 'Rolling';

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'repeatPeriodMs': repeatPeriodMs};

  factory PixelConditionRolling.fromJson(Map<String, dynamic> json) =>
      PixelConditionRolling(repeatPeriodMs: (json['repeatPeriodMs'] as int?) ?? 0);
}

/// Triggers on connect (hello) or disconnect (goodbye) (type=1, 4 bytes).
class PixelConditionHelloGoodbye extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.helloGoodbye;

  /// Bit 0 = hello (connect), bit 1 = goodbye (disconnect).
  int flags;

  PixelConditionHelloGoodbye({this.flags = 1}); // default: hello

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.helloGoodbye.index);
    data.setUint8(offset + 1, flags);
    data.setUint8(offset + 2, 0);
    data.setUint8(offset + 3, 0);
  }

  @override
  String get displayName => switch (flags) {
    1 => 'Connected',
    2 => 'Disconnected',
    _ => 'Connect / Disconnect',
  };

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'flags': flags};

  factory PixelConditionHelloGoodbye.fromJson(Map<String, dynamic> json) =>
      PixelConditionHelloGoodbye(flags: (json['flags'] as int?) ?? 1);
}

/// Triggers while the die is being picked up / handled (type=2, 4 bytes:
/// type + 3 padding, matching the firmware ConditionHandling struct).
class PixelConditionHandling extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.handling;

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.handling.index);
    data.setUint8(offset + 1, 0);
    data.setUint8(offset + 2, 0);
    data.setUint8(offset + 3, 0);
  }

  @override
  String get displayName => 'Handling';

  @override
  Map<String, dynamic> toJson() => {'type': type.name};
}

/// Triggers when the die has landed but is crooked (type=5, 4 bytes:
/// type + 3 padding, matching the firmware ConditionCrooked struct).
class PixelConditionCrooked extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.crooked;

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.crooked.index);
    data.setUint8(offset + 1, 0);
    data.setUint8(offset + 2, 0);
    data.setUint8(offset + 3, 0);
  }

  @override
  String get displayName => 'Crooked';

  @override
  Map<String, dynamic> toJson() => {'type': type.name};
}

/// Triggers when the die has been idle (resting on a face) for a while
/// (type=8, 4 bytes: type + padding + repeatPeriodMs).
class PixelConditionIdle extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.idle;

  /// 0 = fire once, >0 = repeat every N ms while idle.
  int repeatPeriodMs;

  PixelConditionIdle({this.repeatPeriodMs = 0});

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.idle.index);
    data.setUint8(offset + 1, 0);
    data.setUint16(offset + 2, repeatPeriodMs, Endian.little);
  }

  @override
  String get displayName => 'Idle';

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'repeatPeriodMs': repeatPeriodMs};

  factory PixelConditionIdle.fromJson(Map<String, dynamic> json) =>
      PixelConditionIdle(repeatPeriodMs: (json['repeatPeriodMs'] as int?) ?? 0);
}

/// Triggers on BLE connect or disconnect (type=6, 4 bytes).
class PixelConditionConnectionState extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.connection;

  /// Bit 0 = connected, bit 1 = disconnected. Use 3 for both.
  int flags;

  PixelConditionConnectionState({this.flags = 3});

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.connection.index);
    data.setUint8(offset + 1, flags);
    data.setUint16(offset + 2, 0, Endian.little);
  }

  @override
  String get displayName => 'Connection';

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'flags': flags};

  factory PixelConditionConnectionState.fromJson(Map<String, dynamic> json) =>
      PixelConditionConnectionState(flags: (json['flags'] as int?) ?? 3);
}

/// Triggers on battery state changes (type=7, 4 bytes).
/// Flags: low=1, charging=2, done=4, badCharging=8, error=16.
class PixelConditionBatteryState extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.battery;

  int flags;
  int repeatPeriodMs;

  PixelConditionBatteryState({this.flags = 0, this.repeatPeriodMs = 0});

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.battery.index);
    data.setUint8(offset + 1, flags);
    data.setUint16(offset + 2, repeatPeriodMs, Endian.little);
  }

  @override
  String get displayName => 'Battery';

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'flags': flags,
    'repeatPeriodMs': repeatPeriodMs,
  };

  factory PixelConditionBatteryState.fromJson(Map<String, dynamic> json) =>
      PixelConditionBatteryState(
        flags: (json['flags'] as int?) ?? 0,
        repeatPeriodMs: (json['repeatPeriodMs'] as int?) ?? 0,
      );
}
