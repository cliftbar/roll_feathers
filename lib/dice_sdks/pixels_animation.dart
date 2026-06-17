import 'dart:typed_data';
import 'dart:ui' show Color;

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

int _align4(int n) => (n + 3) & ~3;

/// Bernstein (djb2) hash — matches the TypeScript SDK's `computeHash`.
int pixelsBernsteinHash(Uint8List bytes) {
  var hash = 5381;
  for (final b in bytes) {
    hash = (((hash << 5) + hash) ^ b).toUnsigned(32);
  }
  return hash;
}

// ─────────────────────────────────────────────────────────────
// Color
// ─────────────────────────────────────────────────────────────

/// RGB color, 3 bytes on the wire (no alpha).
class PixelColor {
  final int r, g, b;
  const PixelColor(this.r, this.g, this.b);

  factory PixelColor.fromFlutter(Color c) =>
      PixelColor(c.red, c.green, c.blue);

  Color toFlutter() => Color.fromARGB(255, r, g, b);

  /// Serialize 3 bytes.
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, r);
    data.setUint8(offset + 1, g);
    data.setUint8(offset + 2, b);
  }

  static const int byteSize = 3;

  @override
  String toString() => 'PixelColor(r=$r, g=$g, b=$b)';

  @override
  bool operator ==(Object other) =>
      other is PixelColor && r == other.r && g == other.g && b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

// ─────────────────────────────────────────────────────────────
// RgbKeyframe  (2 bytes)
// ─────────────────────────────────────────────────────────────

/// [15:7] = timeMs/2 (9 bits), [6:0] = colorIndex (7 bits, max 127).
class RgbKeyframe {
  final int timeAndColor;

  const RgbKeyframe(this.timeAndColor);

  factory RgbKeyframe.make({required int timeMs, required int colorIndex}) {
    final scaledTime = (timeMs ~/ 2) & 0x1FF;
    return RgbKeyframe((scaledTime << 7) | (colorIndex & 0x7F));
  }

  int get timeMs => ((timeAndColor & 0xFFFF) >> 7) * 2;
  int get colorIndex => timeAndColor & 0x7F;

  void writeTo(ByteData data, int offset) =>
      data.setUint16(offset, timeAndColor, Endian.little);

  static const int byteSize = 2;
}

// ─────────────────────────────────────────────────────────────
// RgbTrack  (8 bytes)
// ─────────────────────────────────────────────────────────────

class RgbTrack {
  final int keyframesOffset;
  final int keyFrameCount;
  final int ledMask;

  const RgbTrack({
    required this.keyframesOffset,
    required this.keyFrameCount,
    required this.ledMask,
  });

  void writeTo(ByteData data, int offset) {
    data.setUint16(offset, keyframesOffset, Endian.little);
    data.setUint8(offset + 2, keyFrameCount);
    data.setUint8(offset + 3, 0); // padding
    data.setUint32(offset + 4, ledMask, Endian.little);
  }

  static const int byteSize = 8;
}

// ─────────────────────────────────────────────────────────────
// SimpleKeyframe  (2 bytes)
// ─────────────────────────────────────────────────────────────

/// [15:7] = timeMs/2 (9 bits), [6:0] = intensity/2 (7 bits).
class SimpleKeyframe {
  final int timeAndIntensity;

  const SimpleKeyframe(this.timeAndIntensity);

  factory SimpleKeyframe.make({required int timeMs, required int intensity}) {
    final scaledTime = (timeMs ~/ 2) & 0x1FF;
    final scaledIntensity = (intensity ~/ 2) & 0x7F;
    return SimpleKeyframe((scaledTime << 7) | scaledIntensity);
  }

  int get timeMs => ((timeAndIntensity & 0xFFFF) >> 7) * 2;
  int get intensity => (timeAndIntensity & 0x7F) * 2;

  void writeTo(ByteData data, int offset) =>
      data.setUint16(offset, timeAndIntensity, Endian.little);

  static const int byteSize = 2;
}

// ─────────────────────────────────────────────────────────────
// Track  (8 bytes)  — same layout as RgbTrack
// ─────────────────────────────────────────────────────────────

class Track {
  final int keyframesOffset;
  final int keyFrameCount;
  final int ledMask;

  const Track({
    required this.keyframesOffset,
    required this.keyFrameCount,
    required this.ledMask,
  });

  void writeTo(ByteData data, int offset) {
    data.setUint16(offset, keyframesOffset, Endian.little);
    data.setUint8(offset + 2, keyFrameCount);
    data.setUint8(offset + 3, 0); // padding
    data.setUint32(offset + 4, ledMask, Endian.little);
  }

  static const int byteSize = 8;
}

// ─────────────────────────────────────────────────────────────
// AnimationBits — shared pool of colors, keyframes, tracks
// ─────────────────────────────────────────────────────────────

class AnimationBits {
  final List<PixelColor> palette = [];
  final List<RgbKeyframe> rgbKeyframes = [];
  final List<RgbTrack> rgbTracks = [];
  final List<SimpleKeyframe> keyframes = [];
  final List<Track> tracks = [];

  /// 0-based index added; returns the index.
  int addColor(PixelColor c) {
    final existing = palette.indexOf(c);
    if (existing >= 0) return existing;
    palette.add(c);
    return palette.length - 1;
  }

  int get paletteSize => palette.length * 3;
  int get rgbKeyframeCount => rgbKeyframes.length;
  int get rgbTrackCount => rgbTracks.length;
  int get keyframeCount => keyframes.length;
  int get trackCount => tracks.length;

  int computeByteSize() =>
      _align4(palette.length * 3) +
      rgbKeyframes.length * RgbKeyframe.byteSize +
      rgbTracks.length * RgbTrack.byteSize +
      keyframes.length * SimpleKeyframe.byteSize +
      tracks.length * Track.byteSize;

  int writeTo(ByteData data, int offset) {
    for (final c in palette) {
      c.writeTo(data, offset);
      offset += PixelColor.byteSize;
    }
    offset = _align4(offset);
    for (final kf in rgbKeyframes) {
      kf.writeTo(data, offset);
      offset += RgbKeyframe.byteSize;
    }
    for (final rt in rgbTracks) {
      rt.writeTo(data, offset);
      offset += RgbTrack.byteSize;
    }
    for (final kf in keyframes) {
      kf.writeTo(data, offset);
      offset += SimpleKeyframe.byteSize;
    }
    for (final t in tracks) {
      t.writeTo(data, offset);
      offset += Track.byteSize;
    }
    return offset;
  }
}

// ─────────────────────────────────────────────────────────────
// Animation types
// ─────────────────────────────────────────────────────────────

enum PixelAnimationType { none, simple, rainbow, keyframed, gradientPattern, gradient, noise, cycle, name, normals, sequence }

/// faceMaskAll = all faces.
const int kFaceMaskAll = 0xFFFFFFFF;

abstract class PixelAnimation {
  PixelAnimationType get type;
  int get byteSize;
  void writeTo(ByteData data, int offset, AnimationBits bits);

  Map<String, dynamic> toJson();
  static PixelAnimation fromJson(Map<String, dynamic> json) {
    final t = PixelAnimationType.values.byName(json['type'] as String);
    return switch (t) {
      PixelAnimationType.simple => PixelAnimationSimple.fromJson(json),
      PixelAnimationType.rainbow => PixelAnimationRainbow.fromJson(json),
      PixelAnimationType.keyframed => PixelAnimationKeyframed.fromJson(json),
      _ => throw UnsupportedError('Unsupported animation type: $t'),
    };
  }
}

/// Simple flash animation (type=1, 12 bytes).
class PixelAnimationSimple extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.simple;

  int animFlags;
  int durationMs;
  int faceMask;
  PixelColor color;
  int count;
  int fade;

  PixelAnimationSimple({
    this.animFlags = 0,
    this.durationMs = 500,
    this.faceMask = kFaceMaskAll,
    PixelColor? color,
    this.count = 1,
    this.fade = 0,
  }) : color = color ?? const PixelColor(255, 255, 255);

  @override
  int get byteSize => 12;

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    final colorIndex = bits.addColor(color);
    data.setUint8(offset, PixelAnimationType.simple.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint32(offset + 4, faceMask, Endian.little);
    data.setUint16(offset + 8, colorIndex, Endian.little);
    data.setUint8(offset + 10, count);
    data.setUint8(offset + 11, fade);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'faceMask': faceMask,
    'colorR': color.r,
    'colorG': color.g,
    'colorB': color.b,
    'count': count,
    'fade': fade,
  };

  factory PixelAnimationSimple.fromJson(Map<String, dynamic> json) =>
      PixelAnimationSimple(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 500,
        faceMask: (json['faceMask'] as int?) ?? kFaceMaskAll,
        color: PixelColor(
          (json['colorR'] as int?) ?? 255,
          (json['colorG'] as int?) ?? 255,
          (json['colorB'] as int?) ?? 255,
        ),
        count: (json['count'] as int?) ?? 1,
        fade: (json['fade'] as int?) ?? 0,
      );
}

/// Rainbow animation (type=2, 12 bytes).
class PixelAnimationRainbow extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.rainbow;

  int animFlags;
  int durationMs;
  int faceMask;
  int count;
  int fade;
  int intensity;
  int cyclesTimes10;

  PixelAnimationRainbow({
    this.animFlags = 0,
    this.durationMs = 1000,
    this.faceMask = kFaceMaskAll,
    this.count = 1,
    this.fade = 0,
    this.intensity = 128,
    this.cyclesTimes10 = 10,
  });

  @override
  int get byteSize => 12;

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.rainbow.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint32(offset + 4, faceMask, Endian.little);
    data.setUint8(offset + 8, count);
    data.setUint8(offset + 9, fade);
    data.setUint8(offset + 10, intensity);
    data.setUint8(offset + 11, cyclesTimes10);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'faceMask': faceMask,
    'count': count,
    'fade': fade,
    'intensity': intensity,
    'cyclesTimes10': cyclesTimes10,
  };

  factory PixelAnimationRainbow.fromJson(Map<String, dynamic> json) =>
      PixelAnimationRainbow(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 1000,
        faceMask: (json['faceMask'] as int?) ?? kFaceMaskAll,
        count: (json['count'] as int?) ?? 1,
        fade: (json['fade'] as int?) ?? 0,
        intensity: (json['intensity'] as int?) ?? 128,
        cyclesTimes10: (json['cyclesTimes10'] as int?) ?? 10,
      );
}

/// Keyframed animation (type=3, 8 bytes).
/// Tracks must be pre-populated in the AnimationBits before writing.
class PixelAnimationKeyframed extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.keyframed;

  int animFlags;
  int durationMs;
  int tracksOffset;
  int trackCount;

  PixelAnimationKeyframed({
    this.animFlags = 0,
    this.durationMs = 1000,
    this.tracksOffset = 0,
    this.trackCount = 0,
  });

  @override
  int get byteSize => 8;

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.keyframed.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint16(offset + 4, tracksOffset, Endian.little);
    data.setUint16(offset + 6, trackCount, Endian.little);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'tracksOffset': tracksOffset,
    'trackCount': trackCount,
  };

  factory PixelAnimationKeyframed.fromJson(Map<String, dynamic> json) =>
      PixelAnimationKeyframed(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 1000,
        tracksOffset: (json['tracksOffset'] as int?) ?? 0,
        trackCount: (json['trackCount'] as int?) ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────
// Conditions
// ─────────────────────────────────────────────────────────────

enum PixelConditionType { none, helloGoodbye, handling, rolling, faceCompare, crooked, connection, battery, idle, rolled }

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

/// Triggers while the die is being picked up / handled (type=2, 2 bytes).
class PixelConditionHandling extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.handling;

  @override
  int get byteSize => 2;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.handling.index);
    data.setUint8(offset + 1, 0);
  }

  @override
  String get displayName => 'Handling';

  @override
  Map<String, dynamic> toJson() => {'type': type.name};
}

/// Triggers when the die is placed crooked (type=5, 1 byte).
class PixelConditionCrooked extends PixelCondition {
  @override
  PixelConditionType get type => PixelConditionType.crooked;

  @override
  int get byteSize => 1;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelConditionType.crooked.index);
  }

  @override
  String get displayName => 'Crooked';

  @override
  Map<String, dynamic> toJson() => {'type': type.name};
}

// ─────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────

enum PixelActionType { none, playAnimation, playAudioClip, makeWebRequest, speakText }

abstract class PixelAction {
  PixelActionType get actionType;
  int get byteSize;
  void writeTo(ByteData data, int offset);
  Map<String, dynamic> toJson();

  static PixelAction fromJson(Map<String, dynamic> json) {
    final t = PixelActionType.values.byName(json['actionType'] as String);
    return switch (t) {
      PixelActionType.playAnimation => PixelActionPlayAnimation.fromJson(json),
      _ => throw UnsupportedError('Unsupported action type: $t'),
    };
  }
}

/// Play an animation from the dataset (type=1, 4 bytes).
class PixelActionPlayAnimation extends PixelAction {
  @override
  PixelActionType get actionType => PixelActionType.playAnimation;

  int animIndex;
  /// -1 = current face.
  int faceIndex;
  int loopCount;

  PixelActionPlayAnimation({
    required this.animIndex,
    this.faceIndex = -1,
    this.loopCount = 1,
  });

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelActionType.playAnimation.index);
    data.setUint8(offset + 1, animIndex);
    data.setInt8(offset + 2, faceIndex);
    data.setUint8(offset + 3, loopCount);
  }

  @override
  Map<String, dynamic> toJson() => {
    'actionType': actionType.name,
    'animIndex': animIndex,
    'faceIndex': faceIndex,
    'loopCount': loopCount,
  };

  factory PixelActionPlayAnimation.fromJson(Map<String, dynamic> json) =>
      PixelActionPlayAnimation(
        animIndex: json['animIndex'] as int,
        faceIndex: (json['faceIndex'] as int?) ?? -1,
        loopCount: (json['loopCount'] as int?) ?? 1,
      );
}

// ─────────────────────────────────────────────────────────────
// Rule  (8 bytes)
// ─────────────────────────────────────────────────────────────

class PixelRule {
  /// High-level model — condition + actions.
  final PixelCondition condition;
  final List<PixelAction> actions;

  const PixelRule({required this.condition, required this.actions});

  Map<String, dynamic> toJson() => {
    'condition': condition.toJson(),
    'actions': actions.map((a) => a.toJson()).toList(),
  };

  factory PixelRule.fromJson(Map<String, dynamic> json) => PixelRule(
    condition: PixelCondition.fromJson(json['condition'] as Map<String, dynamic>),
    actions: (json['actions'] as List)
        .map((a) => PixelAction.fromJson(a as Map<String, dynamic>))
        .toList(),
  );
}

// ─────────────────────────────────────────────────────────────
// PixelProfile  — high-level model stored in app
// ─────────────────────────────────────────────────────────────

class PixelProfile {
  final String id;
  String name;
  int brightness; // 0-255
  final List<PixelAnimation> animations;
  final List<PixelRule> rules;

  PixelProfile({
    required this.id,
    required this.name,
    this.brightness = 255,
    List<PixelAnimation>? animations,
    List<PixelRule>? rules,
  })  : animations = animations ?? [],
        rules = rules ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brightness': brightness,
    'animations': animations.map((a) => a.toJson()).toList(),
    'rules': rules.map((r) => r.toJson()).toList(),
  };

  factory PixelProfile.fromJson(Map<String, dynamic> json) => PixelProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    brightness: (json['brightness'] as int?) ?? 255,
    animations: (json['animations'] as List)
        .map((a) => PixelAnimation.fromJson(a as Map<String, dynamic>))
        .toList(),
    rules: (json['rules'] as List)
        .map((r) => PixelRule.fromJson(r as Map<String, dynamic>))
        .toList(),
  );

  PixelProfile copyWith({String? name, int? brightness}) => PixelProfile(
    id: id,
    name: name ?? this.name,
    brightness: brightness ?? this.brightness,
    animations: List.of(animations),
    rules: List.of(rules),
  );
}

// ─────────────────────────────────────────────────────────────
// DataSet — serializes a PixelProfile to the wire format
// ─────────────────────────────────────────────────────────────

class PixelDataSet {
  final PixelProfile profile;

  const PixelDataSet(this.profile);

  Uint8List toByteArray() {
    final bits = AnimationBits();

    // First pass: write each animation to a staging area to accumulate
    // palette/track data into `bits`, then record sizes.
    // We need the palette to be fully built before we can resolve colorIndex.
    // Two-pass: 1) collect, 2) write.

    // Staging buffers — we write each animation twice (once to collect
    // bit pool entries, once into the final buffer).
    final animationSizes = <int>[];
    for (final anim in profile.animations) {
      animationSizes.add(anim.byteSize);
    }

    final conditionSizes = <int>[];
    for (final rule in profile.rules) {
      conditionSizes.add(rule.condition.byteSize);
    }

    final actionSizes = <int>[];
    for (final rule in profile.rules) {
      for (final action in rule.actions) {
        actionSizes.add(action.byteSize);
      }
    }

    final animationCount = profile.animations.length;
    final conditionCount = profile.rules.length;
    final actionCount = actionSizes.length;
    final ruleCount = profile.rules.length;

    final animationTotalSize = animationSizes.fold(0, (a, b) => a + b);
    final conditionTotalSize = conditionSizes.fold(0, (a, b) => a + b);
    final actionTotalSize = actionSizes.fold(0, (a, b) => a + b);

    // Compute total size
    final bitsSize = bits.computeByteSize(); // may be 0 until we write anims
    // We need a two-pass strategy: compute bits size after writing animations.
    // Write animations to a temp buffer first to populate bits.
    final tempAnimBuf = ByteData(animationTotalSize + 1024);
    var tempOffset = 0;
    for (final anim in profile.animations) {
      anim.writeTo(tempAnimBuf, tempOffset, bits);
      tempOffset += anim.byteSize;
    }

    final finalBitsSize = bits.computeByteSize();
    final totalSize = finalBitsSize +
        _align4(animationCount * 2) + animationTotalSize +
        _align4(conditionCount * 2) + conditionTotalSize +
        _align4(actionCount * 2) + actionTotalSize +
        ruleCount * 8 +
        4; // profile

    final buf = ByteData(totalSize);
    var offset = 0;

    // Animation bits
    offset = bits.writeTo(buf, offset);

    // Animation offsets + data
    var animOffset = 0;
    for (var i = 0; i < profile.animations.length; i++) {
      buf.setUint16(offset + i * 2, animOffset, Endian.little);
      animOffset += animationSizes[i];
    }
    offset = _align4(offset + animationCount * 2);

    // Animations (real write — bits already populated)
    for (final anim in profile.animations) {
      anim.writeTo(buf, offset, bits);
      offset += anim.byteSize;
    }

    // Condition offsets + data
    var condOffset = 0;
    for (var i = 0; i < profile.rules.length; i++) {
      buf.setUint16(offset + i * 2, condOffset, Endian.little);
      condOffset += conditionSizes[i];
    }
    offset = _align4(offset + conditionCount * 2);

    for (final rule in profile.rules) {
      rule.condition.writeTo(buf, offset);
      offset += rule.condition.byteSize;
    }

    // Action offsets + data
    var actOffset = 0;
    var actionIdx = 0;
    for (final rule in profile.rules) {
      for (final action in rule.actions) {
        buf.setUint16(offset + actionIdx * 2, actOffset, Endian.little);
        actOffset += action.byteSize;
        actionIdx++;
      }
    }
    offset = _align4(offset + actionCount * 2);

    for (final rule in profile.rules) {
      for (final action in rule.actions) {
        action.writeTo(buf, offset);
        offset += action.byteSize;
      }
    }

    // Rules (8 bytes each)
    var actionOffsetForRule = 0;
    var actionRunningIdx = 0;
    for (var i = 0; i < profile.rules.length; i++) {
      final rule = profile.rules[i];
      buf.setUint16(offset, i, Endian.little);         // conditionIndex
      buf.setUint16(offset + 2, actionRunningIdx, Endian.little); // actionOffset
      buf.setUint16(offset + 4, rule.actions.length, Endian.little); // actionCount
      buf.setUint16(offset + 6, 0, Endian.little);     // padding
      actionRunningIdx += rule.actions.length;
      offset += 8;
    }

    // Profile (4 bytes)
    buf.setUint16(offset, 0, Endian.little);       // rulesOffset
    buf.setUint16(offset + 2, ruleCount, Endian.little);
    offset += 4;

    return buf.buffer.asUint8List(0, offset);
  }

  /// Serialize only the animations (for instant animation transfer).
  Uint8List toAnimationsByteArray() {
    final bits = AnimationBits();
    final animationSizes = profile.animations.map((a) => a.byteSize).toList();
    final animationCount = profile.animations.length;
    final animationTotalSize = animationSizes.fold(0, (a, b) => a + b);

    // First pass to populate bits
    final tempBuf = ByteData(animationTotalSize + 512);
    var tempOffset = 0;
    for (final anim in profile.animations) {
      anim.writeTo(tempBuf, tempOffset, bits);
      tempOffset += anim.byteSize;
    }

    final finalBitsSize = bits.computeByteSize();
    final totalSize = finalBitsSize + _align4(animationCount * 2) + animationTotalSize;
    final buf = ByteData(totalSize);
    var offset = 0;

    offset = bits.writeTo(buf, offset);

    var animOffset = 0;
    for (var i = 0; i < profile.animations.length; i++) {
      buf.setUint16(offset + i * 2, animOffset, Endian.little);
      animOffset += animationSizes[i];
    }
    offset = _align4(offset + animationCount * 2);

    for (final anim in profile.animations) {
      anim.writeTo(buf, offset, bits);
      offset += anim.byteSize;
    }

    return buf.buffer.asUint8List(0, offset);
  }

  AnimationBits _buildBits() {
    final bits = AnimationBits();
    final tempBuf = ByteData(4096);
    var tempOffset = 0;
    for (final anim in profile.animations) {
      anim.writeTo(tempBuf, tempOffset, bits);
      tempOffset += anim.byteSize;
    }
    return bits;
  }

  /// Stats needed for the TransferAnimationSet header.
  PixelDataSetStats computeStats() {
    final bits = _buildBits();
    final animSize = profile.animations.fold(0, (a, b) => a + b.byteSize);
    int condSize = 0;
    int actCount = 0;
    int actSize = 0;
    for (final rule in profile.rules) {
      condSize += rule.condition.byteSize;
      actCount += rule.actions.length;
      actSize += rule.actions.fold(0, (a, b) => a + b.byteSize);
    }
    return PixelDataSetStats(
      paletteSize: bits.paletteSize,
      rgbKeyFrameCount: bits.rgbKeyframeCount,
      rgbTrackCount: bits.rgbTrackCount,
      keyFrameCount: bits.keyframeCount,
      trackCount: bits.trackCount,
      animationCount: profile.animations.length,
      animationSize: animSize,
      conditionCount: profile.rules.length,
      conditionSize: condSize,
      actionCount: actCount,
      actionSize: actSize,
      ruleCount: profile.rules.length,
      brightness: profile.brightness,
    );
  }

  /// Stats for TransferInstantAnimationSet header.
  PixelInstantDataSetStats computeInstantStats() {
    final bits = _buildBits();
    final animSize = profile.animations.fold(0, (a, b) => a + b.byteSize);
    final data = toAnimationsByteArray();
    return PixelInstantDataSetStats(
      paletteSize: bits.paletteSize,
      rgbKeyFrameCount: bits.rgbKeyframeCount,
      rgbTrackCount: bits.rgbTrackCount,
      keyFrameCount: bits.keyframeCount,
      trackCount: bits.trackCount,
      animationCount: profile.animations.length,
      animationSize: animSize,
      hash: pixelsBernsteinHash(data),
    );
  }
}

class PixelDataSetStats {
  final int paletteSize;
  final int rgbKeyFrameCount;
  final int rgbTrackCount;
  final int keyFrameCount;
  final int trackCount;
  final int animationCount;
  final int animationSize;
  final int conditionCount;
  final int conditionSize;
  final int actionCount;
  final int actionSize;
  final int ruleCount;
  final int brightness;

  const PixelDataSetStats({
    required this.paletteSize,
    required this.rgbKeyFrameCount,
    required this.rgbTrackCount,
    required this.keyFrameCount,
    required this.trackCount,
    required this.animationCount,
    required this.animationSize,
    required this.conditionCount,
    required this.conditionSize,
    required this.actionCount,
    required this.actionSize,
    required this.ruleCount,
    required this.brightness,
  });
}

class PixelInstantDataSetStats {
  final int paletteSize;
  final int rgbKeyFrameCount;
  final int rgbTrackCount;
  final int keyFrameCount;
  final int trackCount;
  final int animationCount;
  final int animationSize;
  final int hash;

  const PixelInstantDataSetStats({
    required this.paletteSize,
    required this.rgbKeyFrameCount,
    required this.rgbTrackCount,
    required this.keyFrameCount,
    required this.trackCount,
    required this.animationCount,
    required this.animationSize,
    required this.hash,
  });
}
