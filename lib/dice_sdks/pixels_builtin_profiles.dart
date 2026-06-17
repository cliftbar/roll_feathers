import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

// Face bitmasks for a d20 (bits 0–19 = faces 1–20)
const int _kAllFaces = 0xFFFFF; // faces 1–20
const int _kTopFace = 0x80000; // face 20
const int _kNonTopFaces = 0x7FFFF; // faces 1–19
const int _kHighFaces = 0xFFC00; // faces 11–20
const int _kLowFaces = 0x3FF; // faces 1–10

/// A built-in profile template.  The [id] field is intentionally blank — callers
/// assign a real UUID when creating a copy for the user's library.
class BuiltinProfile {
  final String name;
  final String description;
  final PixelProfile Function() build;

  const BuiltinProfile({
    required this.name,
    required this.description,
    required this.build,
  });
}

/// All built-in profiles that can be faithfully encoded with the current
/// animation types (Simple + Rainbow).  Profiles requiring AnimNormals,
/// AnimCycle, AnimNoise, or AnimSequence are listed as pending.
final List<BuiltinProfile> kBuiltinProfiles = [
  BuiltinProfile(
    name: 'Default',
    description: 'Rainbow on wake/sleep · white pulse while rolling · white flash on result',
    build: _buildDefault,
  ),
  BuiltinProfile(
    name: 'High / Low',
    description: 'Blue while rolling · green on high roll (11–20) · red on low roll (1–10)',
    build: _buildHighLow,
  ),
  BuiltinProfile(
    name: 'Flashy',
    description: 'White flash while rolling · rapid white on any result · rainbow burst on 20',
    build: _buildFlashy,
  ),
  BuiltinProfile(
    name: 'Rainbow',
    description: 'Rainbow on wake/sleep · rainbow while rolling · rainbow on result',
    build: _buildRainbow,
  ),
];

// ─── Default ─────────────────────────────────────────────────────────────────
// Source: official Pixels app "default" profile (defaultRules.ts)
// Hello/Goodbye: rainbow 2 s · Rolling: white top-face blink 100 ms
// Rolled (any face): white fade 3 s

PixelProfile _buildDefault() => PixelProfile(
  id: '',
  name: 'Default',
  brightness: 255,
  animations: [
    // [0] hello/goodbye: slow rainbow cycle
    PixelAnimationRainbow(durationMs: 2000, intensity: 199, cyclesTimes10: 20),
    // [1] rolling: single white blink on the top LED face
    PixelAnimationSimple(
      durationMs: 100,
      color: const PixelColor(255, 255, 255),
      count: 1,
      fade: 128,
      faceMask: _kTopFace,
    ),
    // [2] rolled: white fade across all LEDs, 3 s
    PixelAnimationSimple(
      durationMs: 3000,
      color: const PixelColor(255, 255, 255),
      count: 1,
      fade: 128,
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
      condition: PixelConditionRolled(faceMask: _kAllFaces),
      actions: [PixelActionPlayAnimation(animIndex: 2, faceIndex: -1)],
    ),
  ],
);

// ─── High / Low ──────────────────────────────────────────────────────────────
// Source: official Pixels app "highLow" profile
// Rolling: blue · Low (1–10): red · High (11–20): green

PixelProfile _buildHighLow() => PixelProfile(
  id: '',
  name: 'High / Low',
  brightness: 255,
  animations: [
    // [0] rolling: blue
    PixelAnimationSimple(
      durationMs: 1000,
      color: const PixelColor(0, 0, 255),
      count: 1,
      fade: 128,
    ),
    // [1] low result (1–10): red
    PixelAnimationSimple(
      durationMs: 1500,
      color: const PixelColor(255, 0, 0),
      count: 1,
      fade: 128,
    ),
    // [2] high result (11–20): green
    PixelAnimationSimple(
      durationMs: 1500,
      color: const PixelColor(0, 255, 0),
      count: 1,
      fade: 128,
    ),
  ],
  rules: [
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 0)],
    ),
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kLowFaces),
      actions: [PixelActionPlayAnimation(animIndex: 1, faceIndex: -1)],
    ),
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kHighFaces),
      actions: [PixelActionPlayAnimation(animIndex: 2, faceIndex: -1)],
    ),
  ],
);

// ─── Flashy ──────────────────────────────────────────────────────────────────
// Source: official Pixels app "flashy" profile
// Rolling: single white blink · any non-20 face: 5× white blinks · face 20: rainbow burst

PixelProfile _buildFlashy() => PixelProfile(
  id: '',
  name: 'Flashy',
  brightness: 255,
  animations: [
    // [0] rolling: single white blink
    PixelAnimationSimple(
      durationMs: 500,
      color: const PixelColor(255, 255, 255),
      count: 1,
      fade: 128,
    ),
    // [1] non-20 result: 5× rapid white blinks
    PixelAnimationSimple(
      durationMs: 500,
      color: const PixelColor(255, 255, 255),
      count: 5,
      fade: 128,
    ),
    // [2] face 20 (nat 20!): fast rainbow burst
    PixelAnimationRainbow(
      durationMs: 3000,
      intensity: 255,
      cyclesTimes10: 30,
    ),
  ],
  rules: [
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 0)],
    ),
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 1, faceIndex: -1)],
    ),
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 2, faceIndex: -1)],
    ),
  ],
);

// ─── Rainbow ─────────────────────────────────────────────────────────────────
// Bonus preset (not in official app): all-rainbow across all conditions

PixelProfile _buildRainbow() => PixelProfile(
  id: '',
  name: 'Rainbow',
  brightness: 255,
  animations: [
    // [0] hello/goodbye: slow rainbow
    PixelAnimationRainbow(durationMs: 2000, intensity: 199, cyclesTimes10: 20),
    // [1] rolling: fast rainbow
    PixelAnimationRainbow(durationMs: 500, intensity: 255, cyclesTimes10: 10),
    // [2] rolled: medium rainbow
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
      condition: PixelConditionRolled(faceMask: _kAllFaces),
      actions: [PixelActionPlayAnimation(animIndex: 2)],
    ),
  ],
);
