import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';

/// A pre-built animation preset. [build] takes the absolute insertion index
/// and returns a list of animations: sub-animations first, primary last.
/// For standalone animations the list has exactly one element.
class BuiltinAnimationPreset {
  final String name;
  final String category;
  final List<PixelAnimation> Function(int baseIndex) build;

  const BuiltinAnimationPreset({
    required this.name,
    required this.category,
    required this.build,
  });
}

// ── Color constants (pre-gamma inputs; gamma-3.0 correction applied inside
// AnimationBits.addColor during serialization) ───────────────────────────────
const _white = PixelColor(179, 179, 179);
const _brightWhite = PixelColor(255, 255, 255);
const _black = PixelColor(0, 0, 0);
const _red = PixelColor(179, 0, 0);
const _brightRed = PixelColor(255, 0, 0);
const _blue = PixelColor(0, 0, 179);
const _brightBlue = PixelColor(0, 0, 255);
const _brightGreen = PixelColor(0, 255, 0);
const _brightYellow = PixelColor(255, 255, 0);
const _brightCyan = PixelColor(0, 255, 255);
const _brightMagenta = PixelColor(255, 0, 255);
const _brightPurple = PixelColor(128, 0, 255);
const _mediumWhite = PixelColor(128, 128, 128);
const _faintWhite = PixelColor(26, 26, 26);
const _orange = PixelColor(179, 89, 0);
const _cyan = PixelColor(0, 179, 179);

// animFlags
const int _traveling = 3; // travelingWithLedIndices
const int _ledIndices = 2; // useLedIndices

// NormalsColorOverrideTypeValues
const int _normFaceToGradient = 1;
const int _normFaceToRainbow = 2;

// NoiseColorOverrideTypeValues
const int _noiseRandomFromGradient = 1;
const int _noiseFaceToRainbow = 3;

// d20 face masks used by alternatingWhite animations
const int _d20Half1 = 91543; // faces [1,2,3,5,8,9,11,14,15,17]
const int _d20Half2 = 957032; // faces [4,6,7,10,12,13,16,18,19,20]

// ── Reusable gradient builders ───────────────────────────────────────────────

PixelGradient _g(List<(int, PixelColor)> kf) => PixelGradient(kf);

PixelGradient _gSolid(PixelColor c) => PixelGradient.solid(c);

PixelGradient _gRainbowAxis() => _g(const [
      (0, _brightRed),
      (200, _brightYellow),
      (400, _brightGreen),
      (600, _brightCyan),
      (800, _brightBlue),
      (1000, _brightMagenta),
    ]);

PixelGradient _gFadeInOut() => _g(const [
      (0, _black),
      (100, _brightWhite),
      (900, _brightWhite),
      (1000, _black),
    ]);

PixelGradient _gAxisBump() => _g(const [
      (0, _black),
      (500, _brightWhite),
      (1000, _black),
    ]);

PixelGradient _gNoiseBlink() => _g(const [
      (0, _black),
      (100, _brightWhite),
      (200, _mediumWhite),
      (1000, _faintWhite),
    ]);

PixelGradient _gSpiralAxis() => _g(const [
      (200, _black),
      (450, _brightWhite),
      (550, _brightWhite),
      (800, _black),
    ]);

PixelGradient _gSpiralAngle() => _g(const [
      (0, _black),
      (400, _brightWhite),
      (800, _black),
    ]);

// ── Rainbow animations ───────────────────────────────────────────────────────

PixelAnimationRainbow _mkRainbow({
  int animFlags = 0,
  required int durationMs,
  required int count,
  int fade = 26,
  required int intensity,
  required int cyclesTimes10,
}) =>
    PixelAnimationRainbow(
      animFlags: animFlags,
      durationMs: durationMs,
      count: count,
      fade: fade,
      intensity: intensity,
      cyclesTimes10: cyclesTimes10,
    );

// ── Noise base ───────────────────────────────────────────────────────────────

PixelAnimationNoise _mkNoise({
  required int durationMs,
  required PixelGradient gradient,
  required PixelGradient blinkGradient,
  required int blinkFrequencyTimes1000,
  int blinkFrequencyVarTimes1000 = 0,
  required int blinkDuration,
  required int fade,
  int gradientColorType = 0,
  int gradientColorVar = 0,
}) =>
    PixelAnimationNoise(
      durationMs: durationMs,
      gradient: gradient,
      blinkGradient: blinkGradient,
      blinkFrequencyTimes1000: blinkFrequencyTimes1000,
      blinkFrequencyVarTimes1000: blinkFrequencyVarTimes1000,
      blinkDuration: blinkDuration,
      fade: fade,
      gradientColorType: gradientColorType,
      gradientColorVar: gradientColorVar,
    );

// ── Normals base ─────────────────────────────────────────────────────────────

PixelAnimationNormals _mkNormals({
  int animFlags = 0,
  required int durationMs,
  required PixelGradient gradient,
  required PixelGradient axisGradient,
  int axisScaleTimes1000 = 1000,
  int axisOffsetTimes1000 = 0,
  int axisScrollSpeedTimes1000 = 0,
  required PixelGradient angleGradient,
  int angleScrollSpeedTimes1000 = 0,
  int fade = 0,
  int mainGradientColorType = 0,
  int mainGradientColorVar = 0,
}) =>
    PixelAnimationNormals(
      animFlags: animFlags,
      durationMs: durationMs,
      gradient: gradient,
      axisGradient: axisGradient,
      axisScaleTimes1000: axisScaleTimes1000,
      axisOffsetTimes1000: axisOffsetTimes1000,
      axisScrollSpeedTimes1000: axisScrollSpeedTimes1000,
      angleGradient: angleGradient,
      angleScrollSpeedTimes1000: angleScrollSpeedTimes1000,
      fade: fade,
      mainGradientColorType: mainGradientColorType,
      mainGradientColorVar: mainGradientColorVar,
    );

// ── Quick normals (quickRed/quickGreen family) ────────────────────────────────

PixelAnimationNormals _mkQuick(PixelGradient axisGrad,
    {required int axisScrollSpeedTimes1000,
    required int axisOffsetTimes1000}) =>
    _mkNormals(
      durationMs: 1000,
      gradient: _gFadeInOut(),
      axisGradient: axisGrad,
      axisScrollSpeedTimes1000: axisScrollSpeedTimes1000,
      axisOffsetTimes1000: axisOffsetTimes1000,
      angleGradient: _g(const [(500, _brightWhite)]),
      angleScrollSpeedTimes1000: 10000,
      fade: 128,
    );

// ── Waterfall shared structure ────────────────────────────────────────────────

PixelAnimationNormals _mkWaterfall({
  required int durationMs,
  required PixelGradient gradient,
  required PixelGradient axisGradient,
  required PixelGradient angleGradient,
  int axisScaleTimes1000 = 2000,
  int axisOffsetTimes1000 = -500,
  int axisScrollSpeedTimes1000 = 2000,
  int angleScrollSpeedTimes1000 = 0,
  int fade = 26,
  int mainGradientColorType = 0,
  int mainGradientColorVar = 0,
}) =>
    _mkNormals(
      durationMs: durationMs,
      gradient: gradient,
      axisGradient: axisGradient,
      axisScaleTimes1000: axisScaleTimes1000,
      axisOffsetTimes1000: axisOffsetTimes1000,
      axisScrollSpeedTimes1000: axisScrollSpeedTimes1000,
      angleGradient: angleGradient,
      angleScrollSpeedTimes1000: angleScrollSpeedTimes1000,
      fade: fade,
      mainGradientColorType: mainGradientColorType,
      mainGradientColorVar: mainGradientColorVar,
    );

// ── White Noise base ─────────────────────────────────────────────────────────

PixelAnimationNoise _mkWhiteNoise() => _mkNoise(
      durationMs: 1500,
      gradient: _g(const [(0, _brightWhite)]),
      blinkGradient: _gNoiseBlink(),
      blinkFrequencyTimes1000: 50000,
      blinkDuration: 255,
      fade: 128,
    );

// ── Shared fountain axisGradient ─────────────────────────────────────────────

PixelGradient _gFountainAxis() => _g(const [
      (0, _black),
      (100, _brightWhite),
      (200, _white),
      (300, _brightWhite),
      (400, _black),
      (500, _white),
      (600, _black),
      (700, _brightWhite),
      (800, _white),
      (900, _brightWhite),
      (1000, _black),
    ]);

PixelGradient _gRainbowFountainAxis() => _g(const [
      (0, _black),
      (100, _brightWhite),
      (200, _white),
      (300, _brightWhite),
      (400, _white),
      (500, _black),
      (600, _white),
      (700, _brightWhite),
      (800, _white),
      (900, _brightWhite),
      (1000, _black),
    ]);

// ── Spinning Magic shared axis gradient ──────────────────────────────────────

PixelGradient _gSpinMagicAxis() => _g(const [
      (0, _black),
      (400, _brightWhite),
      (500, _brightWhite),
      (600, _brightWhite),
      (1000, _black),
    ]);

// ── Individual animation builders ─────────────────────────────────────────────

PixelAnimationNormals _buildWaterfall() => _mkWaterfall(
      durationMs: 2000,
      gradient: _g(const [(0, _black)]),
      axisGradient: _gAxisBump(),
      angleGradient: _gSolid(_brightWhite),
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 100,
    );

PixelAnimationNormals _buildWaterfallGradient() => _mkWaterfall(
      durationMs: 2000,
      gradient: _g(const [
        (0, _red),
        (200, _orange),
        (400, PixelColor(179, 153, 3)),
        (600, _white),
        (800, _cyan),
        (1000, _blue),
      ]),
      axisGradient: _gAxisBump(),
      angleGradient: _gSolid(_brightWhite),
      mainGradientColorType: _normFaceToGradient,
      mainGradientColorVar: 100,
    );

PixelAnimationNormals _buildWaterfallTopHalf() => _mkWaterfall(
      durationMs: 500,
      gradient: _g(const [(0, _black)]),
      axisGradient: _g(const [(200, _black), (1000, _brightWhite)]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 0,
      axisScrollSpeedTimes1000: 0,
      angleGradient: _gSolid(_brightWhite),
      fade: 128,
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 100,
    );

PixelAnimationNormals _buildWaterfallRedGreen() => _mkWaterfall(
      durationMs: 2000,
      gradient: _g(const [
        (0, _brightRed),
        (100, _brightRed),
        (500, _brightYellow),
        (900, _brightGreen),
        (1000, _brightGreen),
      ]),
      axisGradient: _gAxisBump(),
      angleGradient: _gSolid(_brightWhite),
      mainGradientColorType: _normFaceToGradient,
      mainGradientColorVar: 200,
    );

PixelAnimationNormals _buildWaterfallRainbow() => _mkWaterfall(
      durationMs: 2000,
      gradient: _g(const [
        (0, _brightWhite),
        (500, _brightWhite),
        (1000, _black),
      ]),
      axisGradient: _gRainbowAxis(),
      angleGradient: _gSolid(_brightWhite),
      fade: 128,
    );

PixelAnimationNormals _buildSpinning() => _mkNormals(
      durationMs: 3000,
      gradient: _g(const [(0, _brightWhite)]),
      axisGradient: _g(const [(0, _brightWhite)]),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _brightWhite),
        (300, _white),
        (500, _black),
        (700, _white),
        (1000, _brightWhite),
      ]),
      angleScrollSpeedTimes1000: 8000,
      fade: 128,
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 100,
    );

PixelAnimationNormals _buildSpinningRainbow() => _mkNormals(
      durationMs: 5000,
      gradient: _g(const [
        (0, _black),
        (100, _brightWhite),
        (900, _brightWhite),
        (1000, _black),
      ]),
      axisGradient: _g(const [
        (0, _white),
        (500, _brightWhite),
        (1000, _white),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _brightRed),
        (333, _brightGreen),
        (666, _brightBlue),
        (1000, _brightRed),
      ]),
      angleScrollSpeedTimes1000: 10000,
    );

PixelAnimationNormals _buildSpinningRainbowAurora() => _mkNormals(
      durationMs: 5000,
      gradient: _g(const [
        (0, _black),
        (100, _white),
        (900, _white),
        (1000, _black),
      ]),
      axisGradient: _gAxisBump(),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _brightRed),
        (333, _brightGreen),
        (666, _brightBlue),
        (1000, _brightRed),
      ]),
      angleScrollSpeedTimes1000: 10000,
    );

PixelAnimationNormals _buildWhiteRose() => _mkNormals(
      durationMs: 5000,
      gradient: _g(const [
        (0, _black),
        (100, _brightWhite),
        (900, _brightWhite),
        (1000, _black),
      ]),
      axisGradient: _g(const [
        (0, PixelColor(255, 0, 51)),
        (500, PixelColor(255, 128, 128)),
        (1000, _brightWhite),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _brightWhite),
        (500, _brightWhite),
        (1000, _brightWhite),
      ]),
      angleScrollSpeedTimes1000: 0,
    );

PixelAnimationNormals _buildFireViolet() => _mkNormals(
      durationMs: 5000,
      gradient: _gFadeInOut(),
      axisGradient: _g(const [
        (0, _black),
        (300, PixelColor(128, 51, 255)),
        (500, PixelColor(255, 128, 0)),
        (800, PixelColor(255, 204, 128)),
        (920, PixelColor(255, 204, 128)),
        (1000, _black),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _brightWhite),
        (500, _brightWhite),
        (1000, _brightWhite),
      ]),
      angleScrollSpeedTimes1000: 0,
    );

PixelAnimationNormals _buildQuickGreen() => _mkQuick(
      _g(const [
        (0, _black),
        (300, _brightGreen),
        (600, _brightCyan),
        (900, _blue),
        (1000, _black),
      ]),
      axisScrollSpeedTimes1000: -2000,
      axisOffsetTimes1000: 0,
    );

PixelAnimationNormals _buildQuickRed() => _mkQuick(
      _g(const [
        (0, _black),
        (300, _brightRed),
        (600, _brightPurple),
        (900, _brightBlue),
        (1000, _black),
      ]),
      axisScrollSpeedTimes1000: -2000,
      axisOffsetTimes1000: 0,
    );

PixelAnimationNormals _buildReverseQuickRed() => _mkQuick(
      _g(const [
        (0, _black),
        (100, _brightBlue),
        (400, _brightPurple),
        (700, _brightRed),
        (1000, _brightRed),
      ]),
      axisScrollSpeedTimes1000: 2000,
      axisOffsetTimes1000: -1000,
    );

PixelAnimationNormals _buildReverseQuickGreen() => _mkQuick(
      _g(const [
        (0, _black),
        (100, _brightBlue),
        (400, _brightCyan),
        (700, _brightGreen),
        (1000, _brightGreen),
      ]),
      axisScrollSpeedTimes1000: 2000,
      axisOffsetTimes1000: -1000,
    );

PixelAnimationNormals _buildRedGreenAlarm() => _mkNormals(
      durationMs: 2000,
      gradient: _g(const [
        (0, _brightRed),
        (400, _brightRed),
        (600, _brightGreen),
        (1000, _brightGreen),
      ]),
      axisGradient: _g(const [(0, _brightWhite)]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 0,
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _white),
        (200, _brightWhite),
        (400, _white),
        (500, _white),
        (700, _brightWhite),
        (900, _white),
      ]),
      angleScrollSpeedTimes1000: 5000,
      fade: 51,
      mainGradientColorType: _normFaceToGradient,
    );

PixelAnimationNormals _buildRainbowAlarm() => _mkNormals(
      durationMs: 2000,
      gradient: _g(const [(0, _brightWhite), (1000, _brightWhite)]),
      axisGradient: _gRainbowAxis(),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: -500,
      axisScrollSpeedTimes1000: 2000,
      angleGradient: _gAxisBump(),
      angleScrollSpeedTimes1000: 5000,
      fade: 26,
    );

PixelAnimationNormals _buildSpiralUp() => _mkNormals(
      durationMs: 1500,
      gradient: _g(const [(0, _brightWhite), (1000, _brightWhite)]),
      axisGradient: _gSpiralAxis(),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 1100,
      axisScrollSpeedTimes1000: -2200,
      angleGradient: _gSpiralAngle(),
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 200,
    );

PixelAnimationNormals _buildSpiralDown() => _mkNormals(
      durationMs: 1500,
      gradient: _g(const [(0, _brightWhite), (1000, _brightWhite)]),
      axisGradient: _gSpiralAxis(),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: -1200,
      axisScrollSpeedTimes1000: 2200,
      angleGradient: _gSpiralAngle(),
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 200,
    );

PixelAnimationNormals _buildRainbowUp() => _mkNormals(
      durationMs: 3000,
      gradient: _g(const [(0, _brightWhite), (1000, _brightWhite)]),
      axisGradient: _gRainbowAxis(),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 800,
      axisScrollSpeedTimes1000: -2200,
      angleGradient: _gSpiralAngle(),
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
    );

PixelAnimationNormals _buildRainbowDown() => _mkNormals(
      durationMs: 3000,
      gradient: _g(const [(0, _brightWhite), (1000, _brightWhite)]),
      axisGradient: _gRainbowAxis(),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: -800,
      axisScrollSpeedTimes1000: 2200,
      angleGradient: _gSpiralAngle(),
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
    );

PixelAnimationNormals _buildFountain() => _mkNormals(
      durationMs: 2000,
      gradient: _g(const [(0, _black)]),
      axisGradient: _gFountainAxis(),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: 1000,
      axisScrollSpeedTimes1000: -2000,
      angleGradient: _g(const [(100, _brightWhite), (900, _brightWhite)]),
      angleScrollSpeedTimes1000: 0,
      fade: 128,
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 100,
    );

PixelAnimationNormals _buildRainbowFountain() => _mkNormals(
      durationMs: 2000,
      gradient: _g(const [(0, _black)]),
      axisGradient: _gRainbowFountainAxis(),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: 1000,
      axisScrollSpeedTimes1000: -2000,
      angleGradient: _g(const [(100, _brightWhite), (900, _brightWhite)]),
      angleScrollSpeedTimes1000: 0,
      fade: 128,
      mainGradientColorType: _normFaceToRainbow,
      mainGradientColorVar: 500,
    );

PixelAnimationNormals _buildFireBaseLayer() => _mkNormals(
      durationMs: 4500,
      gradient: _g(const [
        (0, _black),
        (100, _brightWhite),
        (700, _brightWhite),
        (1000, _black),
      ]),
      axisGradient: _g(const [
        (0, PixelColor(252, 231, 179)),
        (100, PixelColor(250, 208, 104)),
        (300, PixelColor(241, 162, 4)),
        (500, PixelColor(253, 109, 1)),
        (800, PixelColor(253, 0, 1)),
        (1000, _black),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, _white),
        (200, _brightWhite),
        (400, _white),
        (500, _white),
        (700, _brightWhite),
        (900, _white),
      ]),
      angleScrollSpeedTimes1000: 5000,
    );

PixelAnimationNoise _buildFireNoiseLayer() => _mkNoise(
      durationMs: 5500,
      gradient: _g(const [
        (100, PixelColor(250, 208, 104)),
        (300, PixelColor(241, 162, 4)),
        (700, PixelColor(253, 109, 1)),
      ]),
      blinkGradient: _g(const [
        (0, _black),
        (900, _white),
        (1000, _black),
      ]),
      blinkFrequencyTimes1000: 10000,
      blinkFrequencyVarTimes1000: 1000,
      blinkDuration: 510,
      fade: 255,
    );

PixelAnimationNormals _buildSpinningMagic() => _mkNormals(
      durationMs: 2000,
      gradient: _gFadeInOut(),
      axisGradient: _gSpinMagicAxis(),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, PixelColor(94, 48, 151)),
        (400, _black),
        (500, PixelColor(229, 168, 245)),
        (600, _black),
        (1000, PixelColor(94, 48, 151)),
      ]),
      angleScrollSpeedTimes1000: 3000,
    );

PixelAnimationNormals _buildCounterSpinningMagic() => _mkNormals(
      durationMs: 2000,
      gradient: _gFadeInOut(),
      axisGradient: _gSpinMagicAxis(),
      axisScrollSpeedTimes1000: 0,
      angleGradient: _g(const [
        (0, PixelColor(94, 48, 151)),
        (450, _black),
        (500, PixelColor(159, 99, 169)),
        (550, _black),
        (1000, PixelColor(94, 48, 151)),
      ]),
      angleScrollSpeedTimes1000: 5142,
    );

PixelAnimationNormals _buildWaterBaseLayer() => _mkNormals(
      durationMs: 4500,
      gradient: _g(const [
        (0, _black),
        (100, _brightWhite),
        (700, _brightWhite),
        (1000, _black),
      ]),
      axisGradient: _g(const [
        (0, _white),
        (100, _brightWhite),
        (200, _white),
        (300, _brightWhite),
        (400, _white),
        (500, _brightWhite),
        (600, _white),
        (700, _brightWhite),
        (800, _white),
        (900, _brightWhite),
        (1000, _white),
      ]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: -1000,
      axisScrollSpeedTimes1000: 2000,
      angleGradient: _g(const [
        (0, PixelColor(9, 170, 237)),
        (100, PixelColor(9, 69, 238)),
        (300, PixelColor(9, 170, 237)),
        (500, PixelColor(162, 207, 252)),
        (800, PixelColor(9, 69, 238)),
        (1000, PixelColor(9, 170, 237)),
      ]),
      angleScrollSpeedTimes1000: -1000,
    );

// ── kBuiltinAnimations ────────────────────────────────────────────────────────

final List<BuiltinAnimationPreset> kBuiltinAnimations = [
  // ── Rainbow ×7 ─────────────────────────────────────────────────────────────
  BuiltinAnimationPreset(
    name: 'Rainbow',
    category: 'colorful',
    build: (_) => [
      _mkRainbow(animFlags: _traveling, durationMs: 5000, count: 4,
          intensity: 255, cyclesTimes10: 10),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Aurora',
    category: 'colorful',
    build: (_) => [
      _mkRainbow(animFlags: _traveling, durationMs: 5000, count: 4,
          intensity: 51, cyclesTimes10: 10),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Fast',
    category: 'flashy',
    build: (_) => [
      _mkRainbow(animFlags: _traveling, durationMs: 3000, count: 9,
          intensity: 255, cyclesTimes10: 30),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow All Faces',
    category: 'colorful',
    build: (_) => [
      _mkRainbow(durationMs: 5000, count: 4, intensity: 255, cyclesTimes10: 10),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow All Faces Aurora',
    category: 'colorful',
    build: (_) => [
      _mkRainbow(durationMs: 5000, count: 4, intensity: 51, cyclesTimes10: 10),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow All Faces Fast',
    category: 'flashy',
    build: (_) => [
      _mkRainbow(durationMs: 3000, count: 9, intensity: 255, cyclesTimes10: 30),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Fixed Rainbow',
    category: 'colorful',
    build: (_) => [
      _mkRainbow(animFlags: _traveling, durationMs: 5000, count: 0,
          intensity: 255, cyclesTimes10: 20),
    ],
  ),

  // ── Cycle ×7 ───────────────────────────────────────────────────────────────
  BuiltinAnimationPreset(
    name: 'Cycle Fire',
    category: 'flashy',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 3000,
        count: 5,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 15,
        gradient: _g(const [
          (0, PixelColor(255, 128, 0)),
          (100, PixelColor(255, 204, 0)),
          (200, _black),
          (300, PixelColor(255, 204, 179)),
          (500, PixelColor(255, 204, 0)),
          (800, PixelColor(255, 128, 0)),
        ]),
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Cycle Water',
    category: 'flashy',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 3000,
        count: 6,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 10,
        gradient: _g(const [
          (0, _black),
          (100, PixelColor(77, 77, 255)),
          (300, PixelColor(179, 179, 255)),
          (500, PixelColor(128, 128, 255)),
          (800, _black),
        ]),
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Cycle Magic',
    category: 'flashy',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 3000,
        count: 5,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 50,
        gradient: _g(const [
          (0, _brightBlue),
          (400, PixelColor(229, 168, 245)),
          (500, PixelColor(94, 48, 151)),
          (700, PixelColor(159, 99, 169)),
          (1000, _brightBlue),
        ]),
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Red Blue Worm',
    category: 'animated',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 5000,
        count: 6,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 8,
        gradient: _g(const [
          (0, _black),
          (50, _brightRed),
          (100, PixelColor(77, 77, 255)),
          (800, _black),
        ]),
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Green Blue Worm',
    category: 'animated',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 5000,
        count: 6,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 8,
        gradient: _g(const [
          (0, _black),
          (50, _brightGreen),
          (100, PixelColor(77, 77, 255)),
          (800, _black),
        ]),
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Pink Worm',
    category: 'animated',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 5000,
        count: 6,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 8,
        gradient: _g(const [
          (0, _black),
          (50, _brightWhite),
          (150, PixelColor(255, 128, 128)),
          (800, _black),
        ]),
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Water Worm',
    category: 'animated',
    build: (_) => [
      PixelAnimationCycle(
        animFlags: _ledIndices,
        durationMs: 2000,
        count: 2,
        fade: 128,
        intensity: 255,
        cyclesTimes10: 8,
        gradient: _g(const [
          (0, _black),
          (50, PixelColor(9, 69, 238)),
          (150, PixelColor(162, 207, 252)),
          (250, PixelColor(9, 170, 237)),
          (800, _black),
        ]),
      ),
    ],
  ),

  // ── Noise ×6 ───────────────────────────────────────────────────────────────
  BuiltinAnimationPreset(
    name: 'Noise',
    category: 'flashy',
    build: (_) => [
      _mkNoise(
        durationMs: 2000,
        gradient: _g(const [
          (0, _brightRed),
          (333, _brightGreen),
          (666, _brightBlue),
          (1000, _brightRed),
        ]),
        blinkGradient: _gNoiseBlink(),
        blinkFrequencyTimes1000: 50000,
        blinkDuration: 510,
        fade: 128,
        gradientColorType: _noiseFaceToRainbow,
        gradientColorVar: 20,
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Noise Rainbow',
    category: 'flashy',
    build: (_) => [
      _mkNoise(
        durationMs: 2000,
        gradient: _g(const [
          (0, _brightBlue),
          (333, _brightRed),
          (666, _brightGreen),
          (1000, _brightBlue),
        ]),
        blinkGradient: _gNoiseBlink(),
        blinkFrequencyTimes1000: 40000,
        blinkDuration: 510,
        fade: 26,
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Noise',
    category: 'flashy',
    build: (_) => [
      _mkNoise(
        durationMs: 5000,
        gradient: _gRainbowAxis(),
        blinkGradient: _g(const [
          (0, _black),
          (100, _white),
          (200, _mediumWhite),
          (1000, _faintWhite),
        ]),
        blinkFrequencyTimes1000: 50000,
        blinkDuration: 510,
        fade: 26,
        gradientColorType: _noiseRandomFromGradient,
        gradientColorVar: 0,
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Short Noise',
    category: 'flashy',
    build: (_) => [
      _mkNoise(
        durationMs: 1000,
        gradient: _g(const [
          (0, _brightRed),
          (333, _brightGreen),
          (666, _brightBlue),
          (1000, _brightRed),
        ]),
        blinkGradient: _gNoiseBlink(),
        blinkFrequencyTimes1000: 20000,
        blinkDuration: 255,
        fade: 26,
        gradientColorType: _noiseFaceToRainbow,
        gradientColorVar: 100,
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Fire Noise Layer',
    category: 'flashy',
    build: (_) => [_buildFireNoiseLayer()],
  ),
  BuiltinAnimationPreset(
    name: 'White Noise',
    category: 'flashy',
    build: (_) => [_mkWhiteNoise()],
  ),

  // ── Normals ×26 ────────────────────────────────────────────────────────────
  BuiltinAnimationPreset(
    name: 'Waterfall',
    category: 'animated',
    build: (_) => [_buildWaterfall()],
  ),
  BuiltinAnimationPreset(
    name: 'Waterfall Gradient',
    category: 'animated',
    build: (_) => [_buildWaterfallGradient()],
  ),
  BuiltinAnimationPreset(
    name: 'Waterfall Top Half',
    category: 'animated',
    build: (_) => [_buildWaterfallTopHalf()],
  ),
  BuiltinAnimationPreset(
    name: 'Waterfall Red Green',
    category: 'animated',
    build: (_) => [_buildWaterfallRedGreen()],
  ),
  BuiltinAnimationPreset(
    name: 'Waterfall Rainbow',
    category: 'animated',
    build: (_) => [_buildWaterfallRainbow()],
  ),
  BuiltinAnimationPreset(
    name: 'Spinning',
    category: 'animated',
    build: (_) => [_buildSpinning()],
  ),
  BuiltinAnimationPreset(
    name: 'Spinning Rainbow',
    category: 'animated',
    build: (_) => [_buildSpinningRainbow()],
  ),
  BuiltinAnimationPreset(
    name: 'Spinning Rainbow Aurora',
    category: 'animated',
    build: (_) => [_buildSpinningRainbowAurora()],
  ),
  BuiltinAnimationPreset(
    name: 'White Rose',
    category: 'uniform',
    build: (_) => [_buildWhiteRose()],
  ),
  BuiltinAnimationPreset(
    name: 'Fire Violet',
    category: 'animated',
    build: (_) => [_buildFireViolet()],
  ),
  BuiltinAnimationPreset(
    name: 'Quick Green',
    category: 'uniform',
    build: (_) => [_buildQuickGreen()],
  ),
  BuiltinAnimationPreset(
    name: 'Quick Red',
    category: 'uniform',
    build: (_) => [_buildQuickRed()],
  ),
  BuiltinAnimationPreset(
    name: 'Reverse Quick Red',
    category: 'uniform',
    build: (_) => [_buildReverseQuickRed()],
  ),
  BuiltinAnimationPreset(
    name: 'Reverse Quick Green',
    category: 'uniform',
    build: (_) => [_buildReverseQuickGreen()],
  ),
  BuiltinAnimationPreset(
    name: 'Red Green Alarm',
    category: 'uniform',
    build: (_) => [_buildRedGreenAlarm()],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Alarm',
    category: 'animated',
    build: (_) => [_buildRainbowAlarm()],
  ),
  BuiltinAnimationPreset(
    name: 'Spiral Up',
    category: 'animated',
    build: (_) => [_buildSpiralUp()],
  ),
  BuiltinAnimationPreset(
    name: 'Spiral Down',
    category: 'animated',
    build: (_) => [_buildSpiralDown()],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Up',
    category: 'animated',
    build: (_) => [_buildRainbowUp()],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Down',
    category: 'animated',
    build: (_) => [_buildRainbowDown()],
  ),
  BuiltinAnimationPreset(
    name: 'Fountain',
    category: 'animated',
    build: (_) => [_buildFountain()],
  ),
  BuiltinAnimationPreset(
    name: 'Rainbow Fountain',
    category: 'animated',
    build: (_) => [_buildRainbowFountain()],
  ),
  BuiltinAnimationPreset(
    name: 'Fire Base Layer',
    category: 'animated',
    build: (_) => [_buildFireBaseLayer()],
  ),
  BuiltinAnimationPreset(
    name: 'Spinning Magic',
    category: 'animated',
    build: (_) => [_buildSpinningMagic()],
  ),
  BuiltinAnimationPreset(
    name: 'Counter Spinning Magic',
    category: 'animated',
    build: (_) => [_buildCounterSpinningMagic()],
  ),
  BuiltinAnimationPreset(
    name: 'Water Base Layer',
    category: 'animated',
    build: (_) => [_buildWaterBaseLayer()],
  ),

  // ── Simple flashes ×5 ──────────────────────────────────────────────────────
  BuiltinAnimationPreset(
    name: 'Blue Flash',
    category: 'uniform',
    build: (_) => [
      PixelAnimationSimple(durationMs: 1000, color: _blue, count: 1, fade: 128),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'White Flash',
    category: 'uniform',
    build: (_) => [
      PixelAnimationSimple(
          durationMs: 300, color: _brightWhite, count: 1, fade: 128),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Colored Flash',
    category: 'uniform',
    build: (_) => [
      PixelAnimationSimple(
          durationMs: 500, color: _brightWhite, count: 1, fade: 128,
          faceColor: true),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Alternate White 1',
    category: 'uniform',
    build: (_) => [
      PixelAnimationSimple(
          durationMs: 3000,
          color: _brightWhite,
          count: 5,
          fade: 255,
          faceMask: _d20Half1),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Alternate White 2',
    category: 'uniform',
    build: (_) => [
      PixelAnimationSimple(
          durationMs: 3000,
          color: _brightWhite,
          count: 5,
          fade: 128,
          faceMask: _d20Half2),
    ],
  ),

  // ── Sequences ×11 ──────────────────────────────────────────────────────────
  BuiltinAnimationPreset(
    name: 'Rainbow Fountain X3',
    category: 'animated',
    build: (base) {
      final rf = _buildRainbowFountain();
      return [
        rf,
        PixelAnimationSequence(
          durationMs: 7000,
          entries: [(base, 0), (base, 1400), (base, 2800)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Spiral Up and Down',
    category: 'animated',
    build: (base) => [
      _buildSpiralUp(),
      _buildSpiralDown(),
      PixelAnimationSequence(
        durationMs: 7000,
        entries: [(base, 0), (base + 1, 700)],
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Spiral Up and Down Rainbow',
    category: 'animated',
    build: (base) => [
      _buildRainbowUp(),
      _buildRainbowDown(),
      PixelAnimationSequence(
        durationMs: 7000,
        entries: [(base, 0), (base + 1, 1200)],
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Alternating White',
    category: 'animated',
    build: (base) {
      // orange flash (whiteFlash with color override)
      final orangeFlash = PixelAnimationSimple(
          durationMs: 300, color: const PixelColor(255, 153, 0), count: 1, fade: 128);
      // alternate orange flash (alternatingWhite1_d20 with color override)
      final altOrange = PixelAnimationSimple(
          durationMs: 3000,
          color: const PixelColor(255, 153, 0),
          count: 5,
          fade: 255,
          faceMask: _d20Half1);
      // red flash (alternatingWhite2_d20 with color override)
      final redFlash = PixelAnimationSimple(
          durationMs: 3000,
          color: _brightRed,
          count: 5,
          fade: 128,
          faceMask: _d20Half2);
      return [
        orangeFlash,
        altOrange,
        redFlash,
        PixelAnimationSequence(
          durationMs: 7000,
          entries: [(base, 0), (base + 1, 150), (base + 2, 450)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Noise Rainbow X2',
    category: 'flashy',
    build: (base) {
      // green flash (whiteFlash with color+duration override)
      final greenFlash = PixelAnimationSimple(
          durationMs: 1000, color: _brightGreen, count: 1, fade: 128);
      final nr = _mkNoise(
        durationMs: 2000,
        gradient: _g(const [
          (0, _brightBlue),
          (333, _brightRed),
          (666, _brightGreen),
          (1000, _brightBlue),
        ]),
        blinkGradient: _gNoiseBlink(),
        blinkFrequencyTimes1000: 40000,
        blinkDuration: 510,
        fade: 26,
      );
      return [
        greenFlash,
        nr,
        PixelAnimationSequence(
          durationMs: 7000,
          entries: [(base, 0), (base + 1, 0), (base + 1, 2000)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Fire',
    category: 'animated',
    build: (base) => [
      _buildFireBaseLayer(),
      _buildFireNoiseLayer(),
      PixelAnimationSequence(
        durationMs: 7000,
        entries: [(base, 0), (base + 1, 0)],
      ),
    ],
  ),
  BuiltinAnimationPreset(
    name: 'Overlapping Quick Reds',
    category: 'animated',
    build: (base) {
      final redNoise = _mkNoise(
        durationMs: 1500,
        gradient: _g(const [(0, _brightRed)]),
        blinkGradient: _gNoiseBlink(),
        blinkFrequencyTimes1000: 50000,
        blinkDuration: 255,
        fade: 128,
      );
      return [
        _buildReverseQuickRed(),
        redNoise,
        PixelAnimationSequence(
          durationMs: 2500,
          entries: [(base, 0), (base + 1, 500)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Overlapping Quick Greens',
    category: 'animated',
    build: (base) {
      final rqg = _buildReverseQuickGreen();
      return [
        rqg,
        PixelAnimationSequence(
          durationMs: 2500,
          entries: [(base, 0), (base, 800), (base, 1600)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Rose to Current Face',
    category: 'animated',
    build: (base) {
      final longFlash = PixelAnimationSimple(
          durationMs: 1400, color: _brightWhite, count: 1, fade: 255);
      return [
        longFlash,
        _buildWhiteRose(),
        PixelAnimationSequence(
          durationMs: 2500,
          entries: [(base, 0), (base + 1, 500)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Double Spinning Magic',
    category: 'animated',
    build: (base) {
      final sm = _buildSpinningMagic();
      return [
        sm,
        PixelAnimationSequence(
          durationMs: 2500,
          entries: [(base, 0)],
        ),
      ];
    },
  ),
  BuiltinAnimationPreset(
    name: 'Water Splash',
    category: 'animated',
    build: (base) {
      final longBlueFlash = PixelAnimationSimple(
          durationMs: 2000,
          color: const PixelColor(162, 207, 252),
          count: 1,
          fade: 128);
      return [
        PixelAnimationCycle(
          animFlags: _ledIndices,
          durationMs: 2000,
          count: 2,
          fade: 128,
          intensity: 255,
          cyclesTimes10: 8,
          gradient: _g(const [
            (0, _black),
            (50, PixelColor(9, 69, 238)),
            (150, PixelColor(162, 207, 252)),
            (250, PixelColor(9, 170, 237)),
            (800, _black),
          ]),
        ),
        longBlueFlash,
        PixelAnimationSequence(
          durationMs: 2500,
          entries: [(base, 0), (base + 1, 1000)],
        ),
      ];
    },
  ),
];
