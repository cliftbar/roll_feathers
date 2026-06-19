import 'dart:math' show pow;
import 'dart:typed_data';
import 'dart:ui' show Color;

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

int _align4(int n) => (n + 3) & ~3;

// Gamma-3.0 correction table: index = linear byte (0–255), value = gamma-corrected byte.
final _kGammaTable = List<int>.generate(
  256,
  (i) => (pow(i / 255.0, 3.0) * 255.0).round(),
);

PixelColor _gammaCorrect(PixelColor c) =>
    PixelColor(_kGammaTable[c.r], _kGammaTable[c.g], _kGammaTable[c.b]);

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

  /// Gamma-corrects [c] and adds it to the palette if not already present.
  /// Returns the 0-based palette index of the gamma-corrected color.
  int addColor(PixelColor c) {
    final gammaC = _gammaCorrect(c);
    final existing = palette.indexOf(gammaC);
    if (existing >= 0) return existing;
    palette.add(gammaC);
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

  /// Called once before [writeTo] to populate palette/tracks in [bits].
  /// Default is a no-op; override when the animation needs to add gradient or
  /// track data that must not be added twice.
  void prepareBits(AnimationBits bits) {}

  void writeTo(ByteData data, int offset, AnimationBits bits);

  Map<String, dynamic> toJson();
  static PixelAnimation fromJson(Map<String, dynamic> json) {
    final t = PixelAnimationType.values.byName(json['type'] as String);
    return switch (t) {
      PixelAnimationType.simple => PixelAnimationSimple.fromJson(json),
      PixelAnimationType.rainbow => PixelAnimationRainbow.fromJson(json),
      PixelAnimationType.keyframed => PixelAnimationKeyframed.fromJson(json),
      PixelAnimationType.gradient => PixelAnimationGradient.fromJson(json),
      PixelAnimationType.cycle => PixelAnimationCycle.fromJson(json),
      PixelAnimationType.noise => PixelAnimationNoise.fromJson(json),
      PixelAnimationType.normals => PixelAnimationNormals.fromJson(json),
      PixelAnimationType.gradientPattern => PixelAnimationGradientPattern.fromJson(json),
      PixelAnimationType.sequence => PixelAnimationSequence.fromJson(json),
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
  /// When true, uses palette index 127 (firmware reads die face color).
  bool faceColor;

  PixelAnimationSimple({
    this.animFlags = 0,
    this.durationMs = 500,
    this.faceMask = kFaceMaskAll,
    PixelColor? color,
    this.count = 1,
    this.fade = 0,
    this.faceColor = false,
  }) : color = color ?? const PixelColor(255, 255, 255);

  @override
  int get byteSize => 12;

  int _colorIndex = 0;

  @override
  void prepareBits(AnimationBits bits) {
    _colorIndex = faceColor ? 127 : bits.addColor(color);
  }

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.simple.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint32(offset + 4, faceMask, Endian.little);
    data.setUint16(offset + 8, _colorIndex, Endian.little);
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
    'faceColor': faceColor,
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
        faceColor: (json['faceColor'] as bool?) ?? false,
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
// PixelGradient — sequence of (timeMs, color) keyframes stored
// as an RgbTrack in the AnimationBits pool.
// ─────────────────────────────────────────────────────────────

class PixelGradient {
  /// Each entry is (timeMs, color). Times should span 0–durationMs of the
  /// owning animation (or 0–1000 as a normalized range the firmware stretches).
  final List<(int, PixelColor)> keyframes;

  const PixelGradient(this.keyframes);

  factory PixelGradient.solid(PixelColor color) =>
      PixelGradient([(0, color), (1000, color)]);

  factory PixelGradient.twoColor(PixelColor start, PixelColor end) =>
      PixelGradient([(0, start), (500, end), (1000, start)]);

  static final PixelGradient rainbow = PixelGradient(const [
    (0, PixelColor(255, 0, 0)),
    (167, PixelColor(255, 255, 0)),
    (333, PixelColor(0, 255, 0)),
    (500, PixelColor(0, 255, 255)),
    (667, PixelColor(0, 0, 255)),
    (833, PixelColor(255, 0, 255)),
    (1000, PixelColor(255, 0, 0)),
  ]);

  static final PixelGradient fire = PixelGradient(const [
    (0, PixelColor(255, 20, 0)),
    (333, PixelColor(255, 80, 0)),
    (667, PixelColor(200, 40, 0)),
    (1000, PixelColor(255, 20, 0)),
  ]);

  static final PixelGradient water = PixelGradient(const [
    (0, PixelColor(0, 40, 255)),
    (333, PixelColor(0, 180, 255)),
    (667, PixelColor(0, 100, 200)),
    (1000, PixelColor(0, 40, 255)),
  ]);

  /// Adds this gradient's keyframes and track to [bits]. Returns the rgbTrack
  /// index (i.e. `gradientTrackOffset` to use in the animation header).
  int addToBits(AnimationBits bits) {
    final kfStart = bits.rgbKeyframes.length;
    for (final (timeMs, color) in keyframes) {
      final ci = bits.addColor(color);
      bits.rgbKeyframes.add(RgbKeyframe.make(timeMs: timeMs, colorIndex: ci));
    }
    final trackIdx = bits.rgbTracks.length;
    bits.rgbTracks.add(RgbTrack(
      keyframesOffset: kfStart,
      keyFrameCount: keyframes.length,
      ledMask: 0,
    ));
    return trackIdx;
  }

  Map<String, dynamic> toJson() => {
    'keyframes': keyframes
        .map((kf) => {'t': kf.$1, 'r': kf.$2.r, 'g': kf.$2.g, 'b': kf.$2.b})
        .toList(),
  };

  factory PixelGradient.fromJson(Map<String, dynamic> json) => PixelGradient(
    (json['keyframes'] as List)
        .map((k) => (
          k['t'] as int,
          PixelColor(k['r'] as int, k['g'] as int, k['b'] as int),
        ))
        .toList(),
  );
}

// ─────────────────────────────────────────────────────────────
// Gradient animation (type=5, 12 bytes)
// ─────────────────────────────────────────────────────────────

/// Flowing gradient across LED faces (type=5, 12 bytes).
class PixelAnimationGradient extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.gradient;

  int animFlags;
  int durationMs;
  int faceMask;
  PixelGradient gradient;

  PixelAnimationGradient({
    this.animFlags = 0,
    this.durationMs = 1000,
    this.faceMask = kFaceMaskAll,
    PixelGradient? gradient,
  }) : gradient = gradient ?? PixelGradient.rainbow;

  @override
  int get byteSize => 12;

  int _trackOffset = 0;

  @override
  void prepareBits(AnimationBits bits) {
    _trackOffset = gradient.addToBits(bits);
  }

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.gradient.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint32(offset + 4, faceMask, Endian.little);
    data.setUint16(offset + 8, _trackOffset, Endian.little);
    data.setUint16(offset + 10, 0, Endian.little); // padding
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'faceMask': faceMask,
    'gradient': gradient.toJson(),
  };

  factory PixelAnimationGradient.fromJson(Map<String, dynamic> json) =>
      PixelAnimationGradient(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 1000,
        faceMask: (json['faceMask'] as int?) ?? kFaceMaskAll,
        gradient: json['gradient'] != null
            ? PixelGradient.fromJson(json['gradient'] as Map<String, dynamic>)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────
// Cycle animation (type=7, 14 bytes)
// ─────────────────────────────────────────────────────────────

/// Color-cycling gradient animation (type=7, 14 bytes).
class PixelAnimationCycle extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.cycle;

  int animFlags;
  int durationMs;
  int faceMask;
  int count;
  int fade;
  int intensity;
  int cyclesTimes10;
  PixelGradient gradient;

  PixelAnimationCycle({
    this.animFlags = 0,
    this.durationMs = 2000,
    this.faceMask = kFaceMaskAll,
    this.count = 1,
    this.fade = 0,
    this.intensity = 128,
    this.cyclesTimes10 = 10,
    PixelGradient? gradient,
  }) : gradient = gradient ?? PixelGradient.rainbow;

  @override
  int get byteSize => 14;

  int _trackOffset = 0;

  @override
  void prepareBits(AnimationBits bits) {
    _trackOffset = gradient.addToBits(bits);
  }

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.cycle.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint32(offset + 4, faceMask, Endian.little);
    data.setUint8(offset + 8, count);
    data.setUint8(offset + 9, fade);
    data.setUint8(offset + 10, intensity);
    data.setUint8(offset + 11, cyclesTimes10);
    data.setUint16(offset + 12, _trackOffset, Endian.little);
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
    'gradient': gradient.toJson(),
  };

  factory PixelAnimationCycle.fromJson(Map<String, dynamic> json) =>
      PixelAnimationCycle(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 2000,
        faceMask: (json['faceMask'] as int?) ?? kFaceMaskAll,
        count: (json['count'] as int?) ?? 1,
        fade: (json['fade'] as int?) ?? 0,
        intensity: (json['intensity'] as int?) ?? 128,
        cyclesTimes10: (json['cyclesTimes10'] as int?) ?? 10,
        gradient: json['gradient'] != null
            ? PixelGradient.fromJson(json['gradient'] as Map<String, dynamic>)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────
// Noise animation (type=6, 20 bytes)
// ─────────────────────────────────────────────────────────────

/// Sparkling noise animation (type=6, 20 bytes).
class PixelAnimationNoise extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.noise;

  int animFlags;
  int durationMs;
  PixelGradient gradient;
  PixelGradient blinkGradient;
  int blinkFrequencyTimes1000;
  int blinkFrequencyVarTimes1000;
  int blinkDuration;
  int fade;
  int gradientColorType; // 0 = none
  int gradientColorVar;

  PixelAnimationNoise({
    this.animFlags = 0,
    this.durationMs = 3000,
    PixelGradient? gradient,
    PixelGradient? blinkGradient,
    this.blinkFrequencyTimes1000 = 1000,
    this.blinkFrequencyVarTimes1000 = 500,
    this.blinkDuration = 100,
    this.fade = 128,
    this.gradientColorType = 0,
    this.gradientColorVar = 0,
  })  : gradient = gradient ?? PixelGradient.rainbow,
        blinkGradient = blinkGradient ?? PixelGradient.solid(const PixelColor(255, 255, 255));

  @override
  int get byteSize => 18;

  int _gradTrackOffset = 0;
  int _blinkTrackOffset = 0;

  @override
  void prepareBits(AnimationBits bits) {
    _gradTrackOffset = gradient.addToBits(bits);
    _blinkTrackOffset = blinkGradient.addToBits(bits);
  }

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.noise.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint16(offset + 4, _gradTrackOffset, Endian.little);
    data.setUint16(offset + 6, _blinkTrackOffset, Endian.little);
    data.setUint16(offset + 8, blinkFrequencyTimes1000, Endian.little);
    data.setUint16(offset + 10, blinkFrequencyVarTimes1000, Endian.little);
    data.setUint16(offset + 12, blinkDuration, Endian.little);
    data.setUint8(offset + 14, fade);
    data.setUint8(offset + 15, gradientColorType);
    data.setUint16(offset + 16, gradientColorVar, Endian.little);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'gradient': gradient.toJson(),
    'blinkGradient': blinkGradient.toJson(),
    'blinkFrequencyTimes1000': blinkFrequencyTimes1000,
    'blinkFrequencyVarTimes1000': blinkFrequencyVarTimes1000,
    'blinkDuration': blinkDuration,
    'fade': fade,
    'gradientColorType': gradientColorType,
    'gradientColorVar': gradientColorVar,
  };

  factory PixelAnimationNoise.fromJson(Map<String, dynamic> json) =>
      PixelAnimationNoise(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 3000,
        gradient: json['gradient'] != null
            ? PixelGradient.fromJson(json['gradient'] as Map<String, dynamic>)
            : null,
        blinkGradient: json['blinkGradient'] != null
            ? PixelGradient.fromJson(json['blinkGradient'] as Map<String, dynamic>)
            : null,
        blinkFrequencyTimes1000: (json['blinkFrequencyTimes1000'] as int?) ?? 1000,
        blinkFrequencyVarTimes1000: (json['blinkFrequencyVarTimes1000'] as int?) ?? 500,
        blinkDuration: (json['blinkDuration'] as int?) ?? 100,
        fade: (json['fade'] as int?) ?? 128,
        gradientColorType: (json['gradientColorType'] as int?) ?? 0,
        gradientColorVar: (json['gradientColorVar'] as int?) ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────
// Normals animation (type=9, 22 bytes)
// ─────────────────────────────────────────────────────────────

/// Face-normal-based color animation (type=9, 22 bytes).
class PixelAnimationNormals extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.normals;

  int animFlags;
  int durationMs;
  PixelGradient gradient;
  PixelGradient axisGradient;
  PixelGradient angleGradient;
  int axisScaleTimes1000;
  int axisOffsetTimes1000;
  int axisScrollSpeedTimes1000;
  int angleScrollSpeedTimes1000;
  int fade;
  int mainGradientColorType; // 0 = none
  int mainGradientColorVar;

  PixelAnimationNormals({
    this.animFlags = 0,
    this.durationMs = 3000,
    PixelGradient? gradient,
    PixelGradient? axisGradient,
    PixelGradient? angleGradient,
    this.axisScaleTimes1000 = 1000,
    this.axisOffsetTimes1000 = 0,
    this.axisScrollSpeedTimes1000 = 0,
    this.angleScrollSpeedTimes1000 = 0,
    this.fade = 0,
    this.mainGradientColorType = 0,
    this.mainGradientColorVar = 0,
  })  : gradient = gradient ?? PixelGradient.rainbow,
        axisGradient = axisGradient ?? PixelGradient.solid(const PixelColor(255, 255, 255)),
        angleGradient = angleGradient ?? PixelGradient.solid(const PixelColor(255, 255, 255));

  @override
  int get byteSize => 22;

  int _gradTrackOffset = 0;
  int _axisTrackOffset = 0;
  int _angleTrackOffset = 0;

  @override
  void prepareBits(AnimationBits bits) {
    _gradTrackOffset = gradient.addToBits(bits);
    _axisTrackOffset = axisGradient.addToBits(bits);
    _angleTrackOffset = angleGradient.addToBits(bits);
  }

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.normals.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint16(offset + 4, _gradTrackOffset, Endian.little);
    data.setUint16(offset + 6, _axisTrackOffset, Endian.little);
    data.setUint16(offset + 8, _angleTrackOffset, Endian.little);
    data.setInt16(offset + 10, axisScaleTimes1000, Endian.little);
    data.setInt16(offset + 12, axisOffsetTimes1000, Endian.little);
    data.setInt16(offset + 14, axisScrollSpeedTimes1000, Endian.little);
    data.setInt16(offset + 16, angleScrollSpeedTimes1000, Endian.little);
    data.setUint8(offset + 18, fade);
    data.setUint8(offset + 19, mainGradientColorType);
    data.setUint16(offset + 20, mainGradientColorVar, Endian.little);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'gradient': gradient.toJson(),
    'axisGradient': axisGradient.toJson(),
    'angleGradient': angleGradient.toJson(),
    'axisScaleTimes1000': axisScaleTimes1000,
    'axisOffsetTimes1000': axisOffsetTimes1000,
    'axisScrollSpeedTimes1000': axisScrollSpeedTimes1000,
    'angleScrollSpeedTimes1000': angleScrollSpeedTimes1000,
    'fade': fade,
    'mainGradientColorType': mainGradientColorType,
    'mainGradientColorVar': mainGradientColorVar,
  };

  factory PixelAnimationNormals.fromJson(Map<String, dynamic> json) =>
      PixelAnimationNormals(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 3000,
        gradient: json['gradient'] != null
            ? PixelGradient.fromJson(json['gradient'] as Map<String, dynamic>)
            : null,
        axisGradient: json['axisGradient'] != null
            ? PixelGradient.fromJson(json['axisGradient'] as Map<String, dynamic>)
            : null,
        angleGradient: json['angleGradient'] != null
            ? PixelGradient.fromJson(json['angleGradient'] as Map<String, dynamic>)
            : null,
        axisScaleTimes1000: (json['axisScaleTimes1000'] as int?) ?? 1000,
        axisOffsetTimes1000: (json['axisOffsetTimes1000'] as int?) ?? 0,
        axisScrollSpeedTimes1000: (json['axisScrollSpeedTimes1000'] as int?) ?? 0,
        angleScrollSpeedTimes1000: (json['angleScrollSpeedTimes1000'] as int?) ?? 0,
        fade: (json['fade'] as int?) ?? 0,
        mainGradientColorType: (json['mainGradientColorType'] as int?) ?? 0,
        mainGradientColorVar: (json['mainGradientColorVar'] as int?) ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────
// GradientPattern animation (type=4, 12 bytes)
// ─────────────────────────────────────────────────────────────

/// Grayscale pattern with an RGB gradient overlay (type=4, 12 bytes).
/// [tracksOffset] and [trackCount] reference grayscale Track entries
/// in AnimationBits.tracks; [gradientTrackOffset] references an RgbTrack.
class PixelAnimationGradientPattern extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.gradientPattern;

  int animFlags;
  int durationMs;
  /// Index into AnimationBits.tracks (grayscale tracks). Must be pre-populated.
  int tracksOffset;
  int trackCount;
  PixelGradient gradient;
  bool overrideWithFace;

  PixelAnimationGradientPattern({
    this.animFlags = 0,
    this.durationMs = 2000,
    this.tracksOffset = 0,
    this.trackCount = 0,
    PixelGradient? gradient,
    this.overrideWithFace = false,
  }) : gradient = gradient ?? PixelGradient.rainbow;

  @override
  int get byteSize => 12;

  int _gradTrackOffset = 0;

  @override
  void prepareBits(AnimationBits bits) {
    _gradTrackOffset = gradient.addToBits(bits);
  }

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.gradientPattern.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    data.setUint16(offset + 4, tracksOffset, Endian.little);
    data.setUint16(offset + 6, trackCount, Endian.little);
    data.setUint16(offset + 8, _gradTrackOffset, Endian.little);
    data.setUint8(offset + 10, overrideWithFace ? 1 : 0);
    data.setUint8(offset + 11, 0); // padding
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'tracksOffset': tracksOffset,
    'trackCount': trackCount,
    'gradient': gradient.toJson(),
    'overrideWithFace': overrideWithFace,
  };

  factory PixelAnimationGradientPattern.fromJson(Map<String, dynamic> json) =>
      PixelAnimationGradientPattern(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 2000,
        tracksOffset: (json['tracksOffset'] as int?) ?? 0,
        trackCount: (json['trackCount'] as int?) ?? 0,
        gradient: json['gradient'] != null
            ? PixelGradient.fromJson(json['gradient'] as Map<String, dynamic>)
            : null,
        overrideWithFace: (json['overrideWithFace'] as bool?) ?? false,
      );
}

// ─────────────────────────────────────────────────────────────
// Sequence animation (type=10, 24 bytes)
// ─────────────────────────────────────────────────────────────

/// Sequences up to 4 sub-animations (type=10, 22 bytes).
/// Each entry stores an animation index and delay; indices are written verbatim.
class PixelAnimationSequence extends PixelAnimation {
  @override
  PixelAnimationType get type => PixelAnimationType.sequence;

  int animFlags;
  int durationMs;
  /// Each entry is (animIndex, delayMs). Up to 4 entries.
  final List<(int, int)> entries; // max 4

  PixelAnimationSequence({
    this.animFlags = 0,
    this.durationMs = 0,
    List<(int, int)>? entries,
  }) : entries = entries ?? [];

  @override
  int get byteSize => 22;

  @override
  void writeTo(ByteData data, int offset, AnimationBits bits) {
    data.setUint8(offset, PixelAnimationType.sequence.index);
    data.setUint8(offset + 1, animFlags);
    data.setUint16(offset + 2, durationMs, Endian.little);
    final count = entries.length.clamp(0, 4);
    for (var i = 0; i < 4; i++) {
      final animIdx = i < count ? entries[i].$1 : 0;
      final delay   = i < count ? entries[i].$2 : 0;
      data.setUint16(offset + 4 + i * 4, animIdx, Endian.little);
      data.setUint16(offset + 4 + i * 4 + 2, delay, Endian.little);
    }
    data.setUint16(offset + 20, count, Endian.little);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'animFlags': animFlags,
    'durationMs': durationMs,
    'entries': entries.map((e) => {'animIndex': e.$1, 'delay': e.$2}).toList(),
  };

  factory PixelAnimationSequence.fromJson(Map<String, dynamic> json) =>
      PixelAnimationSequence(
        animFlags: (json['animFlags'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 0,
        entries: (json['entries'] as List? ?? [])
            .map((e) => (e['animIndex'] as int, e['delay'] as int))
            .toList(),
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
      PixelConditionType.connection => PixelConditionConnectionState.fromJson(json),
      PixelConditionType.battery => PixelConditionBatteryState.fromJson(json),
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
      PixelActionType.speakText => PixelActionSpeakText.fromJson(json),
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

/// Speak a text string when triggered (serialized as playAudioClip, type=2, 4 bytes).
/// The actionId (clip ID) is assigned at serialization time to the action's
/// sequential index in the DataSet, matching the TypeScript SDK's encoding.
class PixelActionSpeakText extends PixelAction {
  @override
  PixelActionType get actionType => PixelActionType.speakText;

  String text;
  int actionId = 0;

  PixelActionSpeakText({this.text = ''});

  @override
  int get byteSize => 4;

  @override
  void writeTo(ByteData data, int offset) {
    data.setUint8(offset, PixelActionType.playAudioClip.index); // type = 2
    data.setUint8(offset + 1, 0); // unused
    data.setUint16(offset + 2, actionId, Endian.little);
  }

  @override
  Map<String, dynamic> toJson() => {'actionType': actionType.name, 'text': text};

  factory PixelActionSpeakText.fromJson(Map<String, dynamic> json) =>
      PixelActionSpeakText(text: (json['text'] as String?) ?? '');
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

  /// Bernstein hash of the full serialized profile — matches the die's
  /// `dataSetHash` field in `IAmADie`.
  int computeHash() => pixelsBernsteinHash(toByteArray());

  Uint8List toByteArray() {
    // Pre-pass: assign actionIds to SpeakText actions (matches TS SDK: ruleIdx << 8).
    for (var ruleIdx = 0; ruleIdx < profile.rules.length; ruleIdx++) {
      var actionBase = ruleIdx << 8;
      for (final action in profile.rules[ruleIdx].actions) {
        if (action is PixelActionSpeakText) action.actionId = actionBase;
        actionBase++;
      }
    }

    final bits = AnimationBits();

    // prepareBits populates palette / rgbKeyframes / rgbTracks exactly once.
    for (final anim in profile.animations) {
      anim.prepareBits(bits);
    }

    final animationSizes = profile.animations.map((a) => a.byteSize).toList();

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

    final finalBitsSize = bits.computeByteSize();
    // Match TypeScript SDK: advance by align4(count*2), not align4(offset + count*2).
    // This ensures offset-table SIZE is padded to 4, not the resulting position.
    var totalSize = finalBitsSize;
    totalSize += _align4(animationCount * 2) + animationTotalSize;
    totalSize += _align4(conditionCount * 2) + conditionTotalSize;
    totalSize += _align4(actionCount * 2) + actionTotalSize;
    totalSize += ruleCount * 8 + 4; // rules + profile

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
    offset += _align4(animationCount * 2);

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
    offset += _align4(conditionCount * 2);

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
    offset += _align4(actionCount * 2);

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
    for (final anim in profile.animations) {
      anim.prepareBits(bits);
    }
    final animationSizes = profile.animations.map((a) => a.byteSize).toList();
    final animationCount = profile.animations.length;
    final animationTotalSize = animationSizes.fold(0, (a, b) => a + b);

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
    offset += _align4(animationCount * 2);

    for (final anim in profile.animations) {
      anim.writeTo(buf, offset, bits);
      offset += anim.byteSize;
    }

    return buf.buffer.asUint8List(0, offset);
  }

  AnimationBits _buildBits() {
    final bits = AnimationBits();
    for (final anim in profile.animations) {
      anim.prepareBits(bits);
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
