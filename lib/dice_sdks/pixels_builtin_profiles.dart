import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

// d20 face bitmasks (bit N = face N+1, i.e. face 1 = bit 0)
const int _kAllFaces = 0xFFFFF; // faces 1–20 (bits 0–19)
const int _kTopFace = 0x80000; // face 20 (bit 19)
const int _kNonTopFaces = 0x7FFFF; // faces 1–19 (bits 0–18)
const int _kHighFaces = 0xFFC00; // faces 11–20 (bits 10–19)
const int _kLowFaces = 0x3FF; // faces 1–10 (bits 0–9)
const int _kLowFaceOnly = 0x1; // face 1 only (bit 0)
const int _kMiddleFaces = 0x7FFFE; // faces 2–19 (bits 1–18)

// Worm profile face tiers (thirds of d20 by index 0–19)
const int _kWormLowFaces = 0x7F; // indices 0–6  → faces 1–7
const int _kWormMidFaces = 0x3F80; // indices 7–13 → faces 8–14
const int _kWormHighNonTop = 0x7C000; // indices 14–18 → faces 15–19

// Battery-state condition flags (official SDK: bit 0 is reserved)
const int _kBattLow = 2;
const int _kBattCharging = 4;
const int _kBattDone = 8;
const int _kBattBadCharging = 16;
const int _kBattError = 32;

/// A built-in profile template. The [id] field is intentionally blank — callers
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

final List<BuiltinProfile> kBuiltinProfiles = [
  BuiltinProfile(
    name: 'Default Profile',
    description:
        'Rolling rainbow on wake/sleep · colored flash while rolling · '
        'rainbow on 20 · waterfall on mid faces · red on 1',
    build: _buildDefault,
  ),
  BuiltinProfile(
    name: 'High Low',
    description:
        'Blue while rolling · green burst on high roll (11–20) · red burst on low roll (1–10)',
    build: _buildHighLow,
  ),
  BuiltinProfile(
    name: 'Flashy',
    description:
        'Colored flash while rolling · rapid flashes on any result · rainbow burst on 20',
    build: _buildFlashy,
  ),
  BuiltinProfile(
    name: 'Rainbow',
    description: 'Rainbow on wake/sleep · rainbow while rolling · rainbow on result',
    build: _buildRainbow,
  ),
  BuiltinProfile(
    name: 'Color Cycle',
    description: 'Smooth gradient color cycle on every event',
    build: _buildColorCycle,
  ),
  BuiltinProfile(
    name: 'Empty',
    description: 'Minimal profile: no rolling or rolled animations',
    build: _buildEmpty,
  ),
  BuiltinProfile(
    name: 'Speak Numbers',
    description:
        'Says the rolled number out loud (when the app is open)',
    build: _buildSpeak,
  ),
  BuiltinProfile(
    name: 'Waterfall',
    description: 'Color band scrolls upward using face normals on every event',
    build: _buildWaterfall,
  ),
  BuiltinProfile(
    name: 'Fountain',
    description: 'Light surges upward on every event',
    build: _buildFountain,
  ),
  BuiltinProfile(
    name: 'Spinning',
    description: 'Colors rotate around the die using face normals',
    build: _buildSpinning,
  ),
  BuiltinProfile(
    name: 'Spiral',
    description: 'Colors spiral diagonally — axial flow plus angular rotation',
    build: _buildSpiral,
  ),
  BuiltinProfile(
    name: 'Noise',
    description: 'Sparkling multi-color static effect',
    build: _buildNoise,
  ),
  BuiltinProfile(
    name: 'Worm',
    description: 'A tight band of color crawls across the die surface',
    build: _buildWorm,
  ),
  BuiltinProfile(
    name: 'Rose',
    description: 'Warm pink and magenta gradient shifts with die orientation',
    build: _buildRose,
  ),
  BuiltinProfile(
    name: 'Fire',
    description: 'Flickering fire effect while rolling · blaze on result',
    build: _buildFire,
  ),
  BuiltinProfile(
    name: 'Magic',
    description: 'Spinning magic sparks on every result',
    build: _buildMagic,
  ),
  BuiltinProfile(
    name: 'Water',
    description: 'Blue water splash on every result',
    build: _buildWater,
  ),
];

// ─── Advanced rule animations (7) ────────────────────────────────────────────
// Prepended to every official profile. Indices 0–6 are always these animations.
//
// Colors use pre-gamma input values:
//   Color.blue  = (0, 0, 0.7) → r=0, g=0, b=round(0.7*255)=179
//   Color.red   = (0.7, 0, 0) → r=179, g=0, b=0
//   Color.green = (0, 0.7, 0) → r=0, g=179, b=0
//   Color.yellow = (0.7, 0.6, 0.01) → r=179, g=153, b=3
// AnimationBits.addColor applies gamma-3.0 correction before storing in palette.

List<PixelAnimation> _advancedAnims() => [
  // [0] hello: rolling rainbow, 2 s, 2× count, fade=200/255, intensity=128, cycles=1
  PixelAnimationRainbow(
    animFlags: 3, // traveling | useLedIndices
    durationMs: 2000,
    faceMask: kFaceMaskAll,
    count: 2,
    fade: 200,
    intensity: 128,
    cyclesTimes10: 10,
  ),
  // [1] connection: blue flash ×2, all faces, 1 s
  PixelAnimationSimple(
    durationMs: 1000,
    faceMask: kFaceMaskAll,
    color: const PixelColor(0, 0, 179),
    count: 2,
    fade: 127,
  ),
  // [2] lowBattery: red flash ×3, all faces, 1.5 s — no fade
  PixelAnimationSimple(
    durationMs: 1500,
    faceMask: kFaceMaskAll,
    color: const PixelColor(179, 0, 0),
    count: 3,
    fade: 0,
  ),
  // [3] charging: red flash ×1, top face, 3 s
  PixelAnimationSimple(
    durationMs: 3000,
    faceMask: _kTopFace,
    color: const PixelColor(179, 0, 0),
    count: 1,
    fade: 127,
  ),
  // [4] charged: green flash ×1, top face, 3 s
  PixelAnimationSimple(
    durationMs: 3000,
    faceMask: _kTopFace,
    color: const PixelColor(0, 179, 0),
    count: 1,
    fade: 127,
  ),
  // [5] badCharging: red flash ×10, all faces, 2 s
  PixelAnimationSimple(
    durationMs: 2000,
    faceMask: kFaceMaskAll,
    color: const PixelColor(179, 0, 0),
    count: 10,
    fade: 127,
  ),
  // [6] chargingError: yellow flash ×1, top face, 1 s
  PixelAnimationSimple(
    durationMs: 1000,
    faceMask: _kTopFace,
    color: const PixelColor(179, 153, 3),
    count: 1,
    fade: 127,
  ),
];

// Advanced rules reference animation indices 0–6 (always the same positions).
List<PixelRule> _advancedRules() => [
  // [0] hello/goodbye → hello rainbow (anim 0)
  PixelRule(
    condition: PixelConditionHelloGoodbye(flags: 1), // hello only
    actions: [PixelActionPlayAnimation(animIndex: 0)],
  ),
  // [1] connected | disconnected → connection flash (anim 1)
  PixelRule(
    condition: PixelConditionConnectionState(flags: 3),
    actions: [PixelActionPlayAnimation(animIndex: 1)],
  ),
  // [2] low battery, recheck 30 s → lowBattery flash (anim 2)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _kBattLow, repeatPeriodMs: 30000),
    actions: [PixelActionPlayAnimation(animIndex: 2)],
  ),
  // [3] charging, recheck 5 s → charging flash (anim 3, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _kBattCharging, repeatPeriodMs: 5000),
    actions: [PixelActionPlayAnimation(animIndex: 3, faceIndex: 19)],
  ),
  // [4] fully charged, recheck 5 s → charged flash (anim 4, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _kBattDone, repeatPeriodMs: 5000),
    actions: [PixelActionPlayAnimation(animIndex: 4, faceIndex: 19)],
  ),
  // [5] bad charging, recheck 1 s → badCharging flash (anim 5, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _kBattBadCharging, repeatPeriodMs: 1000),
    actions: [PixelActionPlayAnimation(animIndex: 5, faceIndex: 19)],
  ),
  // [6] charging error, recheck 1.5 s → chargingError flash (anim 6, top face)
  PixelRule(
    condition: PixelConditionBatteryState(flags: _kBattError, repeatPeriodMs: 1500),
    actions: [PixelActionPlayAnimation(animIndex: 6, faceIndex: 19)],
  ),
];

// ─── Default Profile ──────────────────────────────────────────────────────────
// Rolling: coloredFlash (face color, 500 ms recheck)
// Top (face 20): hello rainbow (reuses anim 0)
// Middle (faces 2–19): waterfall
// Low (face 1): quickRed

PixelProfile _buildDefault() => PixelProfile(
  id: '',
  name: 'Default Profile',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] coloredFlash: face-color blink, 500 ms
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
        (0, PixelColor(0, 0, 0)),
        (500, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: -500,
      axisScrollSpeedTimes1000: 2000,
      angleScrollSpeedTimes1000: 0,
      fade: 25,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [9] quickRed — Normals with red→purple→blue axis, scrolling down
    PixelAnimationNormals(
      durationMs: 1000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (300, PixelColor(255, 0, 0)),
        (600, PixelColor(128, 0, 255)),
        (900, PixelColor(0, 0, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [(500, PixelColor(255, 255, 255))]),
      axisScrollSpeedTimes1000: -2000,
      angleScrollSpeedTimes1000: 10000,
      fade: 127,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling (recheck 500 ms) → coloredFlash
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 500),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] rolled top (face 20) → hello rainbow (reuses anim 0)
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 0)],
    ),
    // [9] rolled middle (faces 2–19) → waterfall
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kMiddleFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [10] rolled low (face 1) → quickRed
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kLowFaceOnly),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
  ],
);

// ─── High Low ─────────────────────────────────────────────────────────────────
// Rolling: blueFlash
// Low (1–10): overlappingQuickReds (Sequence)
// High (11–20): overlappingQuickGreens (Sequence)

PixelProfile _buildHighLow() => PixelProfile(
  id: '',
  name: 'High Low',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] blueFlash
    PixelAnimationSimple(
      durationMs: 1000,
      color: const PixelColor(0, 0, 179),
      count: 1,
      fade: 127,
    ),
    // [8] overlappingQuickReds: reverseQuickRed@0 + redNoise@500ms
    PixelAnimationSequence(
      durationMs: 2500,
      entries: const [(9, 0), (10, 500)],
    ),
    // [9] reverseQuickRed (inside overlappingQuickReds)
    PixelAnimationNormals(
      durationMs: 1000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(0, 0, 255)),
        (400, PixelColor(128, 0, 255)),
        (700, PixelColor(255, 0, 0)),
        (1000, PixelColor(255, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [(500, PixelColor(255, 255, 255))]),
      axisOffsetTimes1000: -1000,
      axisScrollSpeedTimes1000: 2000,
      angleScrollSpeedTimes1000: 10000,
      fade: 127,
    ),
    // [10] redNoise (inside overlappingQuickReds)
    PixelAnimationNoise(
      durationMs: 1500,
      gradient: PixelGradient(const [(0, PixelColor(255, 0, 0))]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]),
      blinkFrequencyTimes1000: 50000,
      blinkFrequencyVarTimes1000: 0,
      blinkDuration: 255,
      fade: 127,
    ),
    // [11] overlappingQuickGreens: reverseQuickGreen×3
    PixelAnimationSequence(
      durationMs: 2500,
      entries: const [(12, 0), (12, 800), (12, 1600)],
    ),
    // [12] reverseQuickGreen (inside overlappingQuickGreens)
    PixelAnimationNormals(
      durationMs: 1000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(0, 0, 255)),
        (400, PixelColor(0, 255, 255)),
        (700, PixelColor(0, 255, 0)),
        (1000, PixelColor(0, 255, 0)),
      ]),
      angleGradient: PixelGradient(const [(500, PixelColor(255, 255, 255))]),
      axisOffsetTimes1000: -1000,
      axisScrollSpeedTimes1000: 2000,
      angleScrollSpeedTimes1000: 10000,
      fade: 127,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → blueFlash
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] low faces (1–10) → overlappingQuickReds
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kLowFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] high faces (11–20) → overlappingQuickGreens
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kHighFaces),
      actions: [PixelActionPlayAnimation(animIndex: 11)],
    ),
  ],
);

// ─── Flashy ───────────────────────────────────────────────────────────────────
// Rolling: coloredFlash (face color)
// Non-top: coloredFlash × 5 loops
// Top (nat-20): rainbowAllFacesFast × 2 loops

PixelProfile _buildFlashy() => PixelProfile(
  id: '',
  name: 'Flashy',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] coloredFlash (face color)
    PixelAnimationSimple(
      durationMs: 500,
      faceMask: kFaceMaskAll,
      faceColor: true,
      count: 1,
      fade: 127,
    ),
    // [8] rainbowAllFacesFast: 3 s, count=9, intensity=255, fade=26
    PixelAnimationRainbow(
      durationMs: 3000,
      count: 9,
      intensity: 255,
      fade: 25,
      cyclesTimes10: 10,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → coloredFlash
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] non-top rolled → coloredFlash × 5
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 7, loopCount: 5)],
    ),
    // [9] top rolled → rainbowAllFacesFast × 2
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 8, loopCount: 2)],
    ),
  ],
);

// ─── Rainbow (bonus, no advanced rules) ──────────────────────────────────────

PixelProfile _buildRainbow() => PixelProfile(
  id: '',
  name: 'Rainbow',
  brightness: 255,
  animations: [
    PixelAnimationRainbow(durationMs: 2000, intensity: 199, cyclesTimes10: 20),
    PixelAnimationRainbow(durationMs: 500, intensity: 255, cyclesTimes10: 10),
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

// ─── Color Cycle (bonus, no advanced rules) ───────────────────────────────────

PixelProfile _buildColorCycle() => PixelProfile(
  id: '',
  name: 'Color Cycle',
  brightness: 255,
  animations: [
    PixelAnimationCycle(
      durationMs: 3000,
      faceMask: _kAllFaces,
      intensity: 200,
      cyclesTimes10: 10,
      fade: 0,
      gradient: PixelGradient.rainbow,
    ),
    PixelAnimationCycle(
      durationMs: 800,
      faceMask: _kAllFaces,
      intensity: 255,
      cyclesTimes10: 20,
      fade: 64,
      gradient: PixelGradient.rainbow,
    ),
    PixelAnimationCycle(
      durationMs: 2000,
      faceMask: _kAllFaces,
      intensity: 230,
      cyclesTimes10: 15,
      fade: 0,
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
      condition: PixelConditionRolled(faceMask: _kAllFaces),
      actions: [PixelActionPlayAnimation(animIndex: 2)],
    ),
  ],
);

// ─── Empty ────────────────────────────────────────────────────────────────────
// Official: only 7 advanced rules, no profile-specific rules or animations.

PixelProfile _buildEmpty() => PixelProfile(
  id: '',
  name: 'Empty',
  brightness: 255,
  animations: _advancedAnims(),
  rules: _advancedRules(),
);

// ─── Speak Numbers ────────────────────────────────────────────────────────────
// Non-top: noise · Top: noiseRainbow · 20 SpeakText rules (one per face)

PixelProfile _buildSpeak() => PixelProfile(
  id: '',
  name: 'Speak Numbers',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] noise — dense multi-color sparkle, 2 s
    PixelAnimationNoise(
      durationMs: 2000,
      gradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (333, PixelColor(0, 255, 0)),
        (666, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 0)),
      ]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]),
      blinkFrequencyTimes1000: 50000,
      blinkFrequencyVarTimes1000: 0,
      blinkDuration: 510,
      fade: 127,
      gradientColorType: 3,
      gradientColorVar: 20,
    ),
    // [8] noiseRainbow — blue→red→green sparkle, 2 s
    PixelAnimationNoise(
      durationMs: 2000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 255)),
        (333, PixelColor(255, 0, 0)),
        (666, PixelColor(0, 255, 0)),
        (1000, PixelColor(0, 0, 255)),
      ]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]),
      blinkFrequencyTimes1000: 40000,
      blinkFrequencyVarTimes1000: 0,
      blinkDuration: 510,
      fade: 25,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] non-top rolled → noise
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] top rolled → noiseRainbow
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9–28] speak face 1–20 (SpeakText; actionIds assigned at serialize time)
    for (var f = 1; f <= 20; f++)
      PixelRule(
        condition: PixelConditionRolled(faceMask: 1 << (f - 1)),
        actions: [PixelActionSpeakText(text: '$f')],
      ),
  ],
);

// ─── Waterfall ────────────────────────────────────────────────────────────────

PixelProfile _buildWaterfall() => PixelProfile(
  id: '',
  name: 'Waterfall',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] waterfallTopHalf — brief top-half preview while rolling
    PixelAnimationNormals(
      durationMs: 500,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (200, PixelColor(0, 0, 0)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 0,
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [8] waterfall — band scrolls up
    PixelAnimationNormals(
      durationMs: 2000,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (500, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: -500,
      axisScrollSpeedTimes1000: 2000,
      angleScrollSpeedTimes1000: 0,
      fade: 25,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [9] waterfallRainbow — top face: rainbow axis
    PixelAnimationNormals(
      durationMs: 2000,
      gradient: PixelGradient(const [
        (0, PixelColor(255, 255, 255)),
        (500, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (200, PixelColor(255, 255, 0)),
        (400, PixelColor(0, 255, 0)),
        (600, PixelColor(0, 255, 255)),
        (800, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 255)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: -500,
      axisScrollSpeedTimes1000: 2000,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → waterfallTopHalf
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] non-top rolled → waterfall
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → waterfallRainbow × 3
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 9, loopCount: 3)],
    ),
  ],
);

// ─── Fountain ─────────────────────────────────────────────────────────────────

PixelProfile _buildFountain() => PixelProfile(
  id: '',
  name: 'Fountain',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] waterfallTopHalf (rolling)
    PixelAnimationNormals(
      durationMs: 500,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (200, PixelColor(0, 0, 0)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 0,
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [8] fountain — jets upward (negative scroll)
    PixelAnimationNormals(
      durationMs: 2000,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(179, 179, 179)),
        (300, PixelColor(255, 255, 255)),
        (400, PixelColor(0, 0, 0)),
        (500, PixelColor(179, 179, 179)),
        (600, PixelColor(0, 0, 0)),
        (700, PixelColor(255, 255, 255)),
        (800, PixelColor(179, 179, 179)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
      ]),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: 1000,
      axisScrollSpeedTimes1000: -2000,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [9] rainbowFountainX3 — top face: rainbowFountain×3
    PixelAnimationSequence(
      durationMs: 7000,
      entries: const [(10, 0), (10, 1400), (10, 2800)],
    ),
    // [10] rainbowFountain (inside rainbowFountainX3)
    PixelAnimationNormals(
      durationMs: 2000,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(179, 179, 179)),
        (300, PixelColor(255, 255, 255)),
        (400, PixelColor(179, 179, 179)),
        (500, PixelColor(0, 0, 0)),
        (600, PixelColor(179, 179, 179)),
        (700, PixelColor(255, 255, 255)),
        (800, PixelColor(179, 179, 179)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
      ]),
      axisScaleTimes1000: 2000,
      axisOffsetTimes1000: 1000,
      axisScrollSpeedTimes1000: -2000,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 500,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → waterfallTopHalf
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] non-top rolled → fountain
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → rainbowFountainX3
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
  ],
);

// ─── Spinning ─────────────────────────────────────────────────────────────────

PixelProfile _buildSpinning() => PixelProfile(
  id: '',
  name: 'Spinning',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] waterfallTopHalf (rolling)
    PixelAnimationNormals(
      durationMs: 500,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (200, PixelColor(0, 0, 0)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 1000,
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [8] spinning — angle-scroll with dark band
    PixelAnimationNormals(
      durationMs: 3000,
      gradient: PixelGradient(const [(0, PixelColor(255, 255, 255))]),
      axisGradient: PixelGradient(const [(0, PixelColor(255, 255, 255))]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(255, 255, 255)),
        (300, PixelColor(179, 179, 179)),
        (500, PixelColor(0, 0, 0)),
        (700, PixelColor(179, 179, 179)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      axisScaleTimes1000: 1000,
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 8000,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [9] spinningRainbow — top face
    PixelAnimationNormals(
      durationMs: 5000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(179, 179, 179)),
        (500, PixelColor(255, 255, 255)),
        (1000, PixelColor(179, 179, 179)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (333, PixelColor(0, 255, 0)),
        (666, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 0)),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 10000,
      fade: 0,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → waterfallTopHalf
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] non-top rolled → spinning
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → spinningRainbow
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
  ],
);

// ─── Spiral ───────────────────────────────────────────────────────────────────

PixelProfile _buildSpiral() => PixelProfile(
  id: '',
  name: 'Spiral',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] waterfallTopHalf (rolling)
    PixelAnimationNormals(
      durationMs: 500,
      gradient: PixelGradient(const [(0, PixelColor(0, 0, 0))]),
      axisGradient: PixelGradient(const [
        (200, PixelColor(0, 0, 0)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      angleGradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisScaleTimes1000: 1000,
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 0,
      fade: 127,
      mainGradientColorType: 2,
      mainGradientColorVar: 100,
    ),
    // [8] spiralUpDown: spiralUp@0 + spiralDown@700ms
    PixelAnimationSequence(
      durationMs: 7000,
      entries: const [(9, 0), (10, 700)],
    ),
    // [9] spiralUp
    PixelAnimationNormals(
      durationMs: 1500,
      gradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisGradient: PixelGradient(const [
        (200, PixelColor(0, 0, 0)),
        (450, PixelColor(255, 255, 255)),
        (550, PixelColor(255, 255, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (400, PixelColor(255, 255, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 1100,
      axisScrollSpeedTimes1000: -2200,
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
      mainGradientColorType: 2,
      mainGradientColorVar: 200,
    ),
    // [10] spiralDown
    PixelAnimationNormals(
      durationMs: 1500,
      gradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisGradient: PixelGradient(const [
        (200, PixelColor(0, 0, 0)),
        (450, PixelColor(255, 255, 255)),
        (550, PixelColor(255, 255, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (400, PixelColor(255, 255, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: -1200,
      axisScrollSpeedTimes1000: 2200,
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
      mainGradientColorType: 2,
      mainGradientColorVar: 200,
    ),
    // [11] spiralUpDownRainbow: rainbowUp@0 + rainbowDown@1200ms
    PixelAnimationSequence(
      durationMs: 7000,
      entries: const [(12, 0), (13, 1200)],
    ),
    // [12] rainbowUp
    PixelAnimationNormals(
      durationMs: 3000,
      gradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisGradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (200, PixelColor(255, 255, 0)),
        (400, PixelColor(0, 255, 0)),
        (600, PixelColor(0, 255, 255)),
        (800, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 255)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (400, PixelColor(255, 255, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: 800,
      axisScrollSpeedTimes1000: -2200,
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
      mainGradientColorType: 0,
      mainGradientColorVar: 100,
    ),
    // [13] rainbowDown
    PixelAnimationNormals(
      durationMs: 3000,
      gradient: PixelGradient.solid(const PixelColor(255, 255, 255)),
      axisGradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (200, PixelColor(255, 255, 0)),
        (400, PixelColor(0, 255, 0)),
        (600, PixelColor(0, 255, 255)),
        (800, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 255)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (400, PixelColor(255, 255, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: -800,
      axisScrollSpeedTimes1000: 2200,
      angleScrollSpeedTimes1000: 6000,
      fade: 51,
      mainGradientColorType: 0,
      mainGradientColorVar: 100,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → waterfallTopHalf
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] non-top rolled → spiralUpDown
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → spiralUpDownRainbow
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 11)],
    ),
  ],
);

// ─── Noise ────────────────────────────────────────────────────────────────────

PixelProfile _buildNoise() => PixelProfile(
  id: '',
  name: 'Noise',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] shortNoise — quick sparkle 1 s (rolling)
    PixelAnimationNoise(
      durationMs: 1000,
      gradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (333, PixelColor(0, 255, 0)),
        (666, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 0)),
      ]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]),
      blinkFrequencyTimes1000: 20000,
      blinkFrequencyVarTimes1000: 0,
      blinkDuration: 255,
      fade: 25,
      gradientColorType: 3,
      gradientColorVar: 100,
    ),
    // [8] noise — dense multi-color sparkle 2 s (non-top rolled)
    PixelAnimationNoise(
      durationMs: 2000,
      gradient: PixelGradient(const [
        (0, PixelColor(255, 0, 0)),
        (333, PixelColor(0, 255, 0)),
        (666, PixelColor(0, 0, 255)),
        (1000, PixelColor(255, 0, 0)),
      ]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]),
      blinkFrequencyTimes1000: 50000,
      blinkFrequencyVarTimes1000: 0,
      blinkDuration: 510,
      fade: 127,
      gradientColorType: 3,
      gradientColorVar: 20,
    ),
    // [9] noiseRainbowX2 — top: greenFlash@0 + noiseRainbow@0 + noiseRainbow@2000ms
    PixelAnimationSequence(
      durationMs: 7000,
      entries: const [(10, 0), (11, 0), (11, 2000)],
    ),
    // [10] greenFlash — inside noiseRainbowX2
    PixelAnimationSimple(
      durationMs: 1000,
      color: const PixelColor(0, 255, 0),
      count: 1,
      fade: 127,
    ),
    // [11] noiseRainbow — blue→red→green sparkle
    PixelAnimationNoise(
      durationMs: 2000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 255)),
        (333, PixelColor(255, 0, 0)),
        (666, PixelColor(0, 255, 0)),
        (1000, PixelColor(0, 0, 255)),
      ]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(128, 128, 128)),
        (1000, PixelColor(26, 26, 26)),
      ]),
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
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → noiseRainbowX2
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
  ],
);

// ─── Worm ─────────────────────────────────────────────────────────────────────
// Low tier (faces 1–7): redBlueWorm · Mid (8–14): pinkWorm
// High non-top (15–19): greenBlueWorm · Top (20): rainbowFast

PixelProfile _buildWorm() => PixelProfile(
  id: '',
  name: 'Worm',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] blueFlash (rolling)
    PixelAnimationSimple(
      durationMs: 1000,
      color: const PixelColor(0, 0, 179),
      count: 1,
      fade: 127,
    ),
    // [8] redBlueWorm — low tier
    PixelAnimationCycle(
      animFlags: 2,
      durationMs: 5000,
      count: 6,
      fade: 127,
      intensity: 255,
      cyclesTimes10: 8,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (50, PixelColor(255, 0, 0)),
        (100, PixelColor(77, 77, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
    ),
    // [9] pinkWorm — mid tier
    PixelAnimationCycle(
      animFlags: 2,
      durationMs: 5000,
      count: 6,
      fade: 127,
      intensity: 255,
      cyclesTimes10: 8,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (50, PixelColor(255, 255, 255)),
        (150, PixelColor(255, 128, 128)),
        (800, PixelColor(0, 0, 0)),
      ]),
    ),
    // [10] greenBlueWorm — high non-top tier
    PixelAnimationCycle(
      animFlags: 2,
      durationMs: 5000,
      count: 6,
      fade: 127,
      intensity: 255,
      cyclesTimes10: 8,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (50, PixelColor(0, 255, 0)),
        (100, PixelColor(77, 77, 255)),
        (800, PixelColor(0, 0, 0)),
      ]),
    ),
    // [11] rainbowFast — top
    PixelAnimationRainbow(
      durationMs: 3000,
      animFlags: 3,
      count: 9,
      cyclesTimes10: 30,
      fade: 25,
      intensity: 255,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling → blueFlash
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 200),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [8] low tier → redBlueWorm
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kWormLowFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] mid tier → pinkWorm
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kWormMidFaces),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
    // [10] high non-top → greenBlueWorm
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kWormHighNonTop),
      actions: [PixelActionPlayAnimation(animIndex: 10)],
    ),
    // [11] top → rainbowFast
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 11)],
    ),
  ],
);

// ─── Rose ─────────────────────────────────────────────────────────────────────

PixelProfile _buildRose() => PixelProfile(
  id: '',
  name: 'Rose',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] whiteRose — pink→white axis normals, plays on top face while rolling
    PixelAnimationNormals(
      durationMs: 5000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(255, 0, 51)),
        (500, PixelColor(255, 128, 128)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(255, 255, 255)),
        (500, PixelColor(255, 255, 255)),
        (1000, PixelColor(255, 255, 255)),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 0,
      fade: 0,
    ),
    // [8] roseToCurrentFace: longWhiteFlash@0 + whiteRose@500ms
    PixelAnimationSequence(
      durationMs: 2500,
      entries: const [(9, 0), (7, 500)],
    ),
    // [9] longWhiteFlash — bright white 1.4 s (inside roseToCurrentFace)
    PixelAnimationSimple(
      durationMs: 1400,
      color: const PixelColor(255, 255, 255),
      count: 1,
      fade: 255,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling (1 s recheck) → whiteRose on top face
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 1000),
      actions: [PixelActionPlayAnimation(animIndex: 7, faceIndex: 19, loopCount: 1)],
    ),
    // [8] non-top rolled → roseToCurrentFace
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → roseToCurrentFace
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
  ],
);

// ─── Fire ─────────────────────────────────────────────────────────────────────

PixelProfile _buildFire() => PixelProfile(
  id: '',
  name: 'Fire',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] fire — sequence: fireBaseLayer@0 + fireNoiseLayer@0
    PixelAnimationSequence(
      durationMs: 7000,
      entries: const [(8, 0), (9, 0)],
    ),
    // [8] fireBaseLayer — Normals with warm axis
    PixelAnimationNormals(
      durationMs: 4500,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (700, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(252, 231, 179)),
        (100, PixelColor(250, 208, 104)),
        (300, PixelColor(241, 162, 4)),
        (500, PixelColor(253, 109, 1)),
        (800, PixelColor(253, 0, 1)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(179, 179, 179)),
        (200, PixelColor(255, 255, 255)),
        (400, PixelColor(179, 179, 179)),
        (500, PixelColor(179, 179, 179)),
        (700, PixelColor(255, 255, 255)),
        (900, PixelColor(179, 179, 179)),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 5000,
      fade: 0,
    ),
    // [9] fireNoiseLayer — sparkling heat noise
    PixelAnimationNoise(
      durationMs: 5500,
      gradient: PixelGradient(const [
        (100, PixelColor(250, 208, 104)),
        (300, PixelColor(241, 162, 4)),
        (700, PixelColor(253, 109, 1)),
      ]),
      blinkGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (900, PixelColor(179, 179, 179)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      blinkFrequencyTimes1000: 10000,
      blinkFrequencyVarTimes1000: 1000,
      blinkDuration: 510,
      fade: 255,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling (1 s recheck) → fire
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 1000),
      actions: [PixelActionPlayAnimation(animIndex: 7, loopCount: 1)],
    ),
    // [8] non-top rolled → fire
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
    // [9] top rolled → fire
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 7)],
    ),
  ],
);

// ─── Magic ────────────────────────────────────────────────────────────────────

PixelProfile _buildMagic() => PixelProfile(
  id: '',
  name: 'Magic',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] doubleSpinningMagic — sequence: spinningMagic only
    PixelAnimationSequence(
      durationMs: 2500,
      entries: const [(8, 0)],
    ),
    // [8] spinningMagic — angle-scrolling purple/white normals
    PixelAnimationNormals(
      durationMs: 2000,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (400, PixelColor(255, 255, 255)),
        (500, PixelColor(255, 255, 255)),
        (600, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(94, 48, 151)),
        (400, PixelColor(0, 0, 0)),
        (500, PixelColor(229, 168, 245)),
        (600, PixelColor(0, 0, 0)),
        (1000, PixelColor(94, 48, 151)),
      ]),
      axisScrollSpeedTimes1000: 0,
      angleScrollSpeedTimes1000: 3000,
      fade: 0,
    ),
    // [9] cycleMagic — LED-indexed color cycle with purple gradient
    PixelAnimationCycle(
      animFlags: 2,
      durationMs: 3000,
      count: 5,
      fade: 127,
      intensity: 255,
      cyclesTimes10: 50,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 255)),
        (400, PixelColor(229, 168, 245)),
        (500, PixelColor(94, 48, 151)),
        (700, PixelColor(159, 99, 169)),
        (1000, PixelColor(0, 0, 255)),
      ]),
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling (1 s recheck) → doubleSpinningMagic
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 1000),
      actions: [PixelActionPlayAnimation(animIndex: 7, loopCount: 1)],
    ),
    // [8] non-top rolled → cycleMagic
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
    // [9] top rolled → cycleMagic
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 9)],
    ),
  ],
);

// ─── Water ────────────────────────────────────────────────────────────────────

PixelProfile _buildWater() => PixelProfile(
  id: '',
  name: 'Water',
  brightness: 255,
  animations: [
    ..._advancedAnims(),
    // [7] waterBaseLayer — plays on top face while rolling
    PixelAnimationNormals(
      durationMs: 4500,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (100, PixelColor(255, 255, 255)),
        (700, PixelColor(255, 255, 255)),
        (1000, PixelColor(0, 0, 0)),
      ]),
      axisGradient: PixelGradient(const [
        (0, PixelColor(179, 179, 179)),
        (100, PixelColor(255, 255, 255)),
        (200, PixelColor(179, 179, 179)),
        (300, PixelColor(255, 255, 255)),
        (400, PixelColor(179, 179, 179)),
        (500, PixelColor(255, 255, 255)),
        (600, PixelColor(179, 179, 179)),
        (700, PixelColor(255, 255, 255)),
        (800, PixelColor(179, 179, 179)),
        (900, PixelColor(255, 255, 255)),
        (1000, PixelColor(179, 179, 179)),
      ]),
      angleGradient: PixelGradient(const [
        (0, PixelColor(9, 170, 237)),
        (100, PixelColor(9, 69, 238)),
        (300, PixelColor(9, 170, 237)),
        (500, PixelColor(162, 207, 252)),
        (800, PixelColor(9, 69, 238)),
        (1000, PixelColor(9, 170, 237)),
      ]),
      axisScaleTimes1000: 1000,
      axisOffsetTimes1000: -1000,
      axisScrollSpeedTimes1000: 2000,
      angleScrollSpeedTimes1000: -1000,
      fade: 0,
    ),
    // [8] waterSplash: waterWorm@0 + longBlueFlash@1000ms
    PixelAnimationSequence(
      durationMs: 2500,
      entries: const [(9, 0), (10, 1000)],
    ),
    // [9] waterWorm — Cycle with useLedIndices
    PixelAnimationCycle(
      animFlags: 2,
      durationMs: 2000,
      count: 2,
      fade: 127,
      intensity: 255,
      cyclesTimes10: 8,
      gradient: PixelGradient(const [
        (0, PixelColor(0, 0, 0)),
        (50, PixelColor(9, 69, 238)),
        (150, PixelColor(162, 207, 252)),
        (250, PixelColor(9, 170, 237)),
        (800, PixelColor(0, 0, 0)),
      ]),
    ),
    // [10] longBlueFlash
    PixelAnimationSimple(
      durationMs: 2000,
      color: const PixelColor(162, 207, 252),
      count: 1,
      fade: 127,
    ),
  ],
  rules: [
    ..._advancedRules(),
    // [7] rolling (1 s recheck) → waterBaseLayer on top face
    PixelRule(
      condition: PixelConditionRolling(repeatPeriodMs: 1000),
      actions: [PixelActionPlayAnimation(animIndex: 7, faceIndex: 19, loopCount: 1)],
    ),
    // [8] non-top rolled → waterSplash
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kNonTopFaces),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
    // [9] top rolled → waterSplash
    PixelRule(
      condition: PixelConditionRolled(faceMask: _kTopFace),
      actions: [PixelActionPlayAnimation(animIndex: 8)],
    ),
  ],
);
