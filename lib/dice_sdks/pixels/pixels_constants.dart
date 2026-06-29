// Single home for shared Pixels-protocol constants (magic numbers that the wire
// format and the built-in library content reference). Keeping them here avoids
// the same value being re-spelled — as a raw literal in one place and a named
// constant in another — across the SDK.
//
// This file intentionally has no imports: these are protocol facts, not behavior.
// `pixels_animation.dart` re-exports it, so anything importing that library sees
// these names without a separate import.

// ─── Face masks ───────────────────────────────────────────────────────────────

/// A `PixelConditionRolled` / animation face mask matching every face (all bits).
const int kFaceMaskAll = 0xFFFFFFFF;

// ─── Animation flags (`PixelAnimation.animFlags`) ─────────────────────────────

/// Bit flags for an animation's `animFlags` field.
abstract final class PixelAnimFlags {
  static const int none = 0;
  static const int traveling = 1 << 0; // 1
  static const int useLedIndices = 1 << 1; // 2
  static const int travelingWithLedIndices = traveling | useLedIndices; // 3
}

/// `mainGradientColorType` modes for a Normals animation.
abstract final class PixelNormalsColorType {
  static const int faceToGradient = 1;
  static const int faceToRainbow = 2;
}

/// `gradientColorType` modes for a Noise animation.
abstract final class PixelNoiseColorType {
  static const int randomFromGradient = 1;
  static const int faceToRainbow = 3;
}

// ─── Condition flag bits ──────────────────────────────────────────────────────

/// Bit flags for `PixelConditionBatteryState`.
abstract final class PixelBatteryFlags {
  static const int low = 1 << 1; // 2
  static const int charging = 1 << 2; // 4
  static const int done = 1 << 3; // 8 (fully charged)
  static const int badCharging = 1 << 4; // 16
  static const int error = 1 << 5; // 32
}

/// Bit flags for `PixelConditionHelloGoodbye`.
abstract final class PixelHelloFlags {
  static const int hello = 1 << 0; // 1 (wake up)
  static const int goodbye = 1 << 1; // 2 (sleep)
  static const int both = hello | goodbye; // 3
}

/// Bit flags for `PixelConditionConnectionState`.
abstract final class PixelConnectionFlags {
  static const int connected = 1 << 0; // 1
  static const int disconnected = 1 << 1; // 2
  static const int both = connected | disconnected; // 3
}

// ─── BLE bulk transfer ────────────────────────────────────────────────────────

/// Tuning for the chunked profile/animation upload protocol.
abstract final class PixelTransfer {
  /// Max payload bytes per data chunk written to the die.
  static const int maxChunkSize = 100;

  /// How long to wait for the die's transfer acknowledgement before timing out.
  static const int ackTimeoutMs = 5000;
}
