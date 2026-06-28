/// Manually recreates three built-in profiles by specifying every animation
/// parameter by hand, without using any factory helpers (_advancedAnims etc.).
/// Each test verifies that the manually-constructed DataSet hash matches the
/// official factory output — proving the serialization is complete and correct
/// for all animation types: Rainbow, Simple, Cycle, Noise, Normals, Sequence.
///
/// Run:  flutter test test/pixels_manual_profile_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_constants.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';

// ─── Face mask constants (mirror of private consts in pixels_builtin_profiles) ──
const int _kAll        = 0xFFFFF;  // bits 0–19, all 20 d20 faces
const int _kTopFace    = 0x80000;  // bit 19, face 20
const int _kNonTop     = 0x7FFFF;  // bits 0–18, faces 1–19
const int _kMiddle     = 0x7FFFE;  // bits 1–18, faces 2–19
const int _kLow1       = 0x1;      // bit 0, face 1 only
const int _kHighFaces  = 0xFFC00;  // bits 10–19, faces 11–20
const int _kLowFaces   = 0x3FF;    // bits 0–9, faces 1–10

// Worm-profile tier masks (thirds of d20 by LED index 0–19)
const int _kWormLow    = 0x7F;     // indices 0–6  → faces 1–7
const int _kWormMid    = 0x3F80;   // indices 7–13 → faces 8–14
const int _kWormHighNT = 0x7C000;  // indices 14–18 → faces 15–19

// ─── Battery condition flag constants ───────────────────────────────────────
const int _battLow         = 2;
const int _battCharging    = 4;
const int _battDone        = 8;
const int _battBadCharging = 16;
const int _battError       = 32;

// ─── Helpers ─────────────────────────────────────────────────────────────────

int _officialHash(String name) {
  final preset = kBuiltinProfiles.firstWhere((p) => p.name == name);
  return PixelDataSet(preset.build(PixelDieType.d20)).computeHash().toUnsigned(32);
}

int _manualHash(PixelProfile p) =>
    PixelDataSet(p).computeHash().toUnsigned(32);

/// The 7 advanced animations prepended to every official profile.
List<PixelAnimation> _advancedAnims() => [
  // [0] hello rainbow — traveling rainbow, 2 s, ×2, fade=200, intensity=128
  PixelAnimationRainbow(
    animFlags: 3,  // traveling | useLedIndices
    durationMs: 2000,
    faceMask: kFaceMaskAll,
    count: 2,
    fade: 200,
    intensity: 128,
    cyclesTimes10: 10,
  ),
  // [1] connection flash — blue ×2, all faces, 1 s
  PixelAnimationSimple(
    durationMs: 1000,
    faceMask: kFaceMaskAll,
    color: const PixelColor(0, 0, 179),
    count: 2,
    fade: 127,
  ),
  // [2] low battery flash — red ×3, all faces, 1.5 s, no fade
  PixelAnimationSimple(
    durationMs: 1500,
    faceMask: kFaceMaskAll,
    color: const PixelColor(179, 0, 0),
    count: 3,
    fade: 0,
  ),
  // [3] charging — red ×1, top face, 3 s
  PixelAnimationSimple(
    durationMs: 3000,
    faceMask: _kTopFace,
    color: const PixelColor(179, 0, 0),
    count: 1,
    fade: 127,
  ),
  // [4] fully charged — green ×1, top face, 3 s
  PixelAnimationSimple(
    durationMs: 3000,
    faceMask: _kTopFace,
    color: const PixelColor(0, 179, 0),
    count: 1,
    fade: 127,
  ),
  // [5] bad charging — red ×10, all faces, 2 s
  PixelAnimationSimple(
    durationMs: 2000,
    faceMask: kFaceMaskAll,
    color: const PixelColor(179, 0, 0),
    count: 10,
    fade: 127,
  ),
  // [6] charging error — yellow ×1, top face, 1 s
  PixelAnimationSimple(
    durationMs: 1000,
    faceMask: _kTopFace,
    color: const PixelColor(179, 153, 3),
    count: 1,
    fade: 127,
  ),
];

/// The 7 advanced rules that reference animations 0–6.
List<PixelRule> _advancedRules() => [
  // [0] hello → hello rainbow (anim 0)
  PixelRule(
    condition: PixelConditionHelloGoodbye(flags: 1),
    actions: [PixelActionPlayAnimation(animIndex: 0)],
  ),
  // [1] connected/disconnected → connection flash (anim 1)
  PixelRule(
    condition: PixelConditionConnectionState(flags: 3),
    actions: [PixelActionPlayAnimation(animIndex: 1)],
  ),
  // [2] low battery (recheck 30 s) → low battery flash (anim 2)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _battLow, repeatPeriodMs: 30000),
    actions: [PixelActionPlayAnimation(animIndex: 2)],
  ),
  // [3] charging (recheck 5 s) → charging (anim 3, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _battCharging, repeatPeriodMs: 5000),
    actions: [PixelActionPlayAnimation(animIndex: 3, faceIndex: 19)],
  ),
  // [4] fully charged (recheck 5 s) → charged (anim 4, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _battDone, repeatPeriodMs: 5000),
    actions: [PixelActionPlayAnimation(animIndex: 4, faceIndex: 19)],
  ),
  // [5] bad charging (recheck 1 s) → badCharging (anim 5, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _battBadCharging, repeatPeriodMs: 1000),
    actions: [PixelActionPlayAnimation(animIndex: 5, faceIndex: 19)],
  ),
  // [6] charging error (recheck 1.5 s) → chargingError (anim 6, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _battError, repeatPeriodMs: 1500),
    actions: [PixelActionPlayAnimation(animIndex: 6, faceIndex: 19)],
  ),
];

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('manual profile reconstruction — hash parity', () {
    // ── Color Cycle ─────────────────────────────────────────────────────────
    // Simplest profile: no advanced animations, 3 PixelAnimationCycle + 3 rules.
    test('Color Cycle — PixelAnimationCycle', () {
      final profile = PixelProfile(
        id: '',
        name: 'Color Cycle',
        brightness: 255,
        animations: [
          // [0] slow cycle — hello/goodbye
          PixelAnimationCycle(
            durationMs: 3000,
            faceMask: _kAll,
            count: 1,
            fade: 0,
            intensity: 200,
            cyclesTimes10: 10,
            gradient: PixelGradient.rainbow,
          ),
          // [1] fast cycle — rolling
          PixelAnimationCycle(
            durationMs: 800,
            faceMask: _kAll,
            count: 1,
            fade: 64,
            intensity: 255,
            cyclesTimes10: 20,
            gradient: PixelGradient.rainbow,
          ),
          // [2] mid cycle — rolled result
          PixelAnimationCycle(
            durationMs: 2000,
            faceMask: _kAll,
            count: 1,
            fade: 0,
            intensity: 230,
            cyclesTimes10: 15,
            gradient: PixelGradient.rainbow,
          ),
        ],
        rules: [
          PixelRule(
            condition: PixelConditionHelloGoodbye(flags: 3),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
          PixelRule(
            condition: PixelConditionRolling(repeatPeriodMs: 200),
            actions: [PixelActionPlayAnimation(animIndex: 1)],
          ),
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kAll),
            actions: [PixelActionPlayAnimation(animIndex: 2)],
          ),
        ],
      );

      expect(_manualHash(profile), equals(_officialHash('Color Cycle')),
          reason: 'Color Cycle manual hash must match official factory');
    });

    // ── Default Profile ──────────────────────────────────────────────────────
    // 7 advanced anims + coloredFlash (Simple/faceColor) + waterfall (Normals)
    // + quickRed (Normals). Exercises Rainbow, Simple (with faceColor), Normals.
    test('Default Profile — Rainbow + Simple + Normals', () {
      final profile = PixelProfile(
        id: '',
        name: 'Default Profile',
        brightness: 255,
        animations: [
          ..._advancedAnims(),

          // [7] coloredFlash — face-color solid flash, 500 ms
          PixelAnimationSimple(
            durationMs: 500,
            faceMask: kFaceMaskAll,
            faceColor: true,
            count: 1,
            fade: 127,
          ),

          // [8] waterfall — face-normal gradient band scrolling upward
          PixelAnimationNormals(
            durationMs: 2000,
            gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
            axisGradient: PixelGradient(const [
              (0,    PixelColor(0, 0, 0)),
              (500,  PixelColor(255, 255, 255)),
              (1000, PixelColor(0, 0, 0)),
            ]),
            angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
            axisScaleTimes1000: 2000,
            axisOffsetTimes1000: -500,
            axisScrollSpeedTimes1000: 2000,
            angleScrollSpeedTimes1000: 0,
            fade: 25,
            mainGradientColorType: 2,  // faceToRainbow
            mainGradientColorVar: 100,
          ),

          // [9] quickRed — red→purple→blue axis scrolling downward
          PixelAnimationNormals(
            durationMs: 1000,
            gradient: PixelGradient(const [
              (0,    PixelColor(0, 0, 0)),
              (100,  PixelColor(255, 255, 255)),
              (900,  PixelColor(255, 255, 255)),
              (1000, PixelColor(0, 0, 0)),
            ]),
            axisGradient: PixelGradient(const [
              (0,   PixelColor(0, 0, 0)),
              (300, PixelColor(255, 0, 0)),
              (600, PixelColor(128, 0, 255)),
              (900, PixelColor(0, 0, 255)),
              (1000,PixelColor(0, 0, 0)),
            ]),
            angleGradient: PixelGradient(const [(500, PixelColor(255, 255, 255))]),
            axisScrollSpeedTimes1000: -2000,
            angleScrollSpeedTimes1000: 10000,
            fade: 127,
          ),
        ],
        rules: [
          ..._advancedRules(),
          // [7] rolling (500 ms recheck) → coloredFlash
          PixelRule(
            condition: PixelConditionRolling(repeatPeriodMs: 500),
            actions: [PixelActionPlayAnimation(animIndex: 7)],
          ),
          // [8] rolled top (face 20) → hello rainbow (anim 0)
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kTopFace),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
          // [9] rolled middle (faces 2–19) → waterfall
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kMiddle),
            actions: [PixelActionPlayAnimation(animIndex: 8)],
          ),
          // [10] rolled low (face 1) → quickRed
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kLow1),
            actions: [PixelActionPlayAnimation(animIndex: 9)],
          ),
        ],
      );

      expect(_manualHash(profile), equals(_officialHash('Default Profile')),
          reason: 'Default Profile manual hash must match official factory');
    });

    // ── Noise ────────────────────────────────────────────────────────────────
    // 7 advanced anims + shortNoise (Noise) + noise (Noise) +
    // noiseRainbowX2 (Sequence) + greenFlash (Simple) + noiseRainbow (Noise).
    // Exercises Noise + Sequence together.
    test('Noise — PixelAnimationNoise + PixelAnimationSequence', () {
      // Shared blink gradient used by all three Noise animations.
      PixelGradient blinkGrad() => PixelGradient(const [
        (0,    PixelColor(0, 0, 0)),
        (100,  PixelColor(255, 255, 255)),
        (200,  PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]);

      // RGB cycle gradient used by shortNoise and noise.
      PixelGradient rgbCycleGrad() => PixelGradient(const [
        (0,    PixelColor(255, 0, 0)),
        (333,  PixelColor(0, 255, 0)),
        (666,  PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 0)),
      ]);

      final profile = PixelProfile(
        id: '',
        name: 'Noise',
        brightness: 255,
        animations: [
          ..._advancedAnims(),

          // [7] shortNoise — quick sparkle, 1 s, rolling trigger
          PixelAnimationNoise(
            durationMs: 1000,
            gradient: rgbCycleGrad(),
            blinkGradient: blinkGrad(),
            blinkFrequencyTimes1000: 20000,
            blinkFrequencyVarTimes1000: 0,
            blinkDuration: 255,
            fade: 25,
            gradientColorType: 3,  // faceToRainbow
            gradientColorVar: 100,
          ),

          // [8] noise — dense sparkle, 2 s, non-top roll trigger
          PixelAnimationNoise(
            durationMs: 2000,
            gradient: rgbCycleGrad(),
            blinkGradient: blinkGrad(),
            blinkFrequencyTimes1000: 50000,
            blinkFrequencyVarTimes1000: 0,
            blinkDuration: 510,
            fade: 127,
            gradientColorType: 3,
            gradientColorVar: 20,
          ),

          // [9] noiseRainbowX2 — Sequence: greenFlash@0 + noiseRainbow×2, top face
          PixelAnimationSequence(
            durationMs: 7000,
            entries: const [(10, 0), (11, 0), (11, 2000)],
          ),

          // [10] greenFlash — inside noiseRainbowX2 sequence
          PixelAnimationSimple(
            durationMs: 1000,
            color: const PixelColor(0, 255, 0),
            count: 1,
            fade: 127,
          ),

          // [11] noiseRainbow — blue→red→green sparkle, 2 s
          PixelAnimationNoise(
            durationMs: 2000,
            gradient: PixelGradient(const [
              (0,    PixelColor(0, 0, 255)),
              (333,  PixelColor(255, 0, 0)),
              (666,  PixelColor(0, 255, 0)),
              (1000, PixelColor(0, 0, 255)),
            ]),
            blinkGradient: blinkGrad(),
            blinkFrequencyTimes1000: 40000,
            blinkFrequencyVarTimes1000: 0,
            blinkDuration: 510,
            fade: 25,
          ),
        ],
        rules: [
          ..._advancedRules(),
          // [7] rolling → shortNoise
          PixelRule(
            condition: PixelConditionRolling(repeatPeriodMs: 200),
            actions: [PixelActionPlayAnimation(animIndex: 7)],
          ),
          // [8] non-top rolled → noise
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kNonTop),
            actions: [PixelActionPlayAnimation(animIndex: 8)],
          ),
          // [9] top rolled → noiseRainbowX2 sequence
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kTopFace),
            actions: [PixelActionPlayAnimation(animIndex: 9)],
          ),
        ],
      );

      expect(_manualHash(profile), equals(_officialHash('Noise')),
          reason: 'Noise profile manual hash must match official factory');
    });

    // ── Rainbow ──────────────────────────────────────────────────────────────
    // Simplest built-in with no advanced animations: 3 PixelAnimationRainbow +
    // 3 rules. Clean isolation test for the Rainbow type.
    test('Rainbow — PixelAnimationRainbow only (no advanced anims)', () {
      final profile = PixelProfile(
        id: '',
        name: 'Rainbow',
        brightness: 255,
        animations: [
          // [0] hello/goodbye — slow, lower intensity
          PixelAnimationRainbow(durationMs: 2000, intensity: 199, cyclesTimes10: 20),
          // [1] rolling — fast, full intensity
          PixelAnimationRainbow(durationMs: 500, intensity: 255, cyclesTimes10: 10),
          // [2] rolled result — 2 s full intensity
          PixelAnimationRainbow(durationMs: 2000, intensity: 255, cyclesTimes10: 10),
        ],
        rules: [
          PixelRule(
            condition: PixelConditionHelloGoodbye(flags: 3),
            actions: [PixelActionPlayAnimation(animIndex: 0)],
          ),
          PixelRule(
            condition: PixelConditionRolling(repeatPeriodMs: 200),
            actions: [PixelActionPlayAnimation(animIndex: 1)],
          ),
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kAll),
            actions: [PixelActionPlayAnimation(animIndex: 2)],
          ),
        ],
      );

      expect(_manualHash(profile), equals(_officialHash('Rainbow')),
          reason: 'Rainbow manual hash must match official factory');
    });

    // ── Worm ─────────────────────────────────────────────────────────────────
    // 7 advanced anims + blueFlash (Simple) + redBlueWorm / pinkWorm /
    // greenBlueWorm (Cycle with animFlags:2 = useLedIndices) + rainbowFast.
    // Tests the animFlags:2 Cycle variant not exercised in Color Cycle.
    test('Worm — PixelAnimationCycle animFlags:2 + per-tier face masks', () {
      final profile = PixelProfile(
        id: '',
        name: 'Worm',
        brightness: 255,
        animations: [
          ..._advancedAnims(),

          // [7] blueFlash — rolling indicator
          PixelAnimationSimple(
            durationMs: 1000,
            color: const PixelColor(0, 0, 179),
            count: 1,
            fade: 127,
          ),

          // [8] redBlueWorm — low tier (faces 1–7)
          PixelAnimationCycle(
            animFlags: 2,
            durationMs: 5000,
            count: 6,
            fade: 127,
            intensity: 255,
            cyclesTimes10: 8,
            gradient: PixelGradient(const [
              (0,   PixelColor(0, 0, 0)),
              (50,  PixelColor(255, 0, 0)),
              (100, PixelColor(77, 77, 255)),
              (800, PixelColor(0, 0, 0)),
            ]),
          ),

          // [9] pinkWorm — mid tier (faces 8–14)
          PixelAnimationCycle(
            animFlags: 2,
            durationMs: 5000,
            count: 6,
            fade: 127,
            intensity: 255,
            cyclesTimes10: 8,
            gradient: PixelGradient(const [
              (0,   PixelColor(0, 0, 0)),
              (50,  PixelColor(255, 255, 255)),
              (150, PixelColor(255, 128, 128)),
              (800, PixelColor(0, 0, 0)),
            ]),
          ),

          // [10] greenBlueWorm — high non-top tier (faces 15–19)
          PixelAnimationCycle(
            animFlags: 2,
            durationMs: 5000,
            count: 6,
            fade: 127,
            intensity: 255,
            cyclesTimes10: 8,
            gradient: PixelGradient(const [
              (0,   PixelColor(0, 0, 0)),
              (50,  PixelColor(0, 255, 0)),
              (100, PixelColor(77, 77, 255)),
              (800, PixelColor(0, 0, 0)),
            ]),
          ),

          // [11] rainbowFast — top (face 20), traveling, ×9 loops
          PixelAnimationRainbow(
            animFlags: 3,
            durationMs: 3000,
            count: 9,
            cyclesTimes10: 30,
            fade: 25,
            intensity: 255,
          ),
        ],
        rules: [
          ..._advancedRules(),
          PixelRule(
            condition: PixelConditionRolling(repeatPeriodMs: 200),
            actions: [PixelActionPlayAnimation(animIndex: 7)],
          ),
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kWormLow),
            actions: [PixelActionPlayAnimation(animIndex: 8)],
          ),
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kWormMid),
            actions: [PixelActionPlayAnimation(animIndex: 9)],
          ),
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kWormHighNT),
            actions: [PixelActionPlayAnimation(animIndex: 10)],
          ),
          PixelRule(
            condition: PixelConditionRolled(faceMask: _kTopFace),
            actions: [PixelActionPlayAnimation(animIndex: 11)],
          ),
        ],
      );

      expect(_manualHash(profile), equals(_officialHash('Worm')),
          reason: 'Worm manual hash must match official factory');
    });
  });

  // ─── Synthetic tests for types not used in any built-in profile ──────────────
  // PixelAnimationGradient, PixelAnimationKeyframed, and
  // PixelAnimationGradientPattern have no official built-in to compare against.
  // These tests verify that:
  //   (a) identical constructions produce the same hash (serialization determinism)
  //   (b) different parameters produce different hashes (differentiation)
  group('synthetic serialization — types absent from built-ins', () {
    // Helper: minimal one-animation profile with a single Rolled rule.
    PixelProfile _oneAnim(String name, PixelAnimation anim) => PixelProfile(
      id: '',
      name: name,
      brightness: 255,
      animations: [anim],
      rules: [
        PixelRule(
          condition: PixelConditionRolled(faceMask: _kAll),
          actions: [PixelActionPlayAnimation(animIndex: 0)],
        ),
      ],
    );

    // ── PixelAnimationGradient (type=5) ─────────────────────────────────────
    // A flowing gradient applied uniformly across selected LED faces.
    // No built-in profile uses this type directly.
    test('PixelAnimationGradient — deterministic + differentiable', () {
      final pRainbow = _oneAnim('g', PixelAnimationGradient(
        durationMs: 2000, faceMask: _kAll, gradient: PixelGradient.rainbow,
      ));
      final pRainbow2 = _oneAnim('g', PixelAnimationGradient(
        durationMs: 2000, faceMask: _kAll, gradient: PixelGradient.rainbow,
      ));
      final pFire = _oneAnim('g', PixelAnimationGradient(
        durationMs: 2000, faceMask: _kAll, gradient: PixelGradient.fire,
      ));
      final pShorter = _oneAnim('g', PixelAnimationGradient(
        durationMs: 1000, faceMask: _kAll, gradient: PixelGradient.rainbow,
      ));

      expect(_manualHash(pRainbow), equals(_manualHash(pRainbow2)),
          reason: 'identical Gradient → same hash');
      expect(_manualHash(pRainbow), isNot(equals(_manualHash(pFire))),
          reason: 'different gradient color → different hash');
      expect(_manualHash(pRainbow), isNot(equals(_manualHash(pShorter))),
          reason: 'different durationMs → different hash');
    });

    // ── PixelAnimationKeyframed (type=3) ─────────────────────────────────────
    // References named PixelPattern entries. pattern=null → no LED tracks
    // (valid empty animation). Tests determinism and flag/duration differentiation.
    test('PixelAnimationKeyframed — deterministic + differentiable', () {
      final p0 = _oneAnim('k', PixelAnimationKeyframed(
        animFlags: 0, durationMs: 1000,
      ));
      final p0b = _oneAnim('k', PixelAnimationKeyframed(
        animFlags: 0, durationMs: 1000,
      ));
      final p1 = _oneAnim('k', PixelAnimationKeyframed(
        animFlags: 1, durationMs: 1000,
      ));
      final pLong = _oneAnim('k', PixelAnimationKeyframed(
        animFlags: 0, durationMs: 2000,
      ));

      expect(_manualHash(p0), equals(_manualHash(p0b)),
          reason: 'identical Keyframed → same hash');
      expect(_manualHash(p0), isNot(equals(_manualHash(p1))),
          reason: 'different animFlags → different hash');
      expect(_manualHash(p0), isNot(equals(_manualHash(pLong))),
          reason: 'different durationMs → different hash');
    });

    // ── PixelAnimationGradientPattern (type=9) ───────────────────────────────
    // Applies a gradient to per-LED grayscale tracks from a PixelPattern.
    // pattern=null → no LED tracks; gradient still controls the color overlay.
    test('PixelAnimationGradientPattern — deterministic + differentiable', () {
      final pR = _oneAnim('gp', PixelAnimationGradientPattern(
        durationMs: 2000,
        gradient: PixelGradient.rainbow, overrideWithFace: false,
      ));
      final pR2 = _oneAnim('gp', PixelAnimationGradientPattern(
        durationMs: 2000,
        gradient: PixelGradient.rainbow, overrideWithFace: false,
      ));
      final pFire = _oneAnim('gp', PixelAnimationGradientPattern(
        durationMs: 2000,
        gradient: PixelGradient.fire, overrideWithFace: false,
      ));
      final pFace = _oneAnim('gp', PixelAnimationGradientPattern(
        durationMs: 2000,
        gradient: PixelGradient.rainbow, overrideWithFace: true,
      ));

      expect(_manualHash(pR), equals(_manualHash(pR2)),
          reason: 'identical GradientPattern → same hash');
      expect(_manualHash(pR), isNot(equals(_manualHash(pFire))),
          reason: 'different gradient → different hash');
      expect(_manualHash(pR), isNot(equals(_manualHash(pFace))),
          reason: 'overrideWithFace=true → different hash');
    });
  });
}
