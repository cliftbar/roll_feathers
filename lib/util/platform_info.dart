import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWasm, kIsWeb;

/// Host platform facts, resolved once (via [PlatformInfo.host]) at composition
/// time and injected where behavior depends on the platform. Centralizing the
/// checks keeps them consolidated and makes platform-dependent logic testable —
/// tests construct a [PlatformInfo] with explicit flags instead of branching on
/// the real host.
class PlatformInfo {
  /// Running on the web (true for both JS and WebAssembly compilation targets).
  final bool isWeb;

  /// Running on a WebAssembly web build specifically. Implies [isWeb].
  final bool isWasm;
  final bool isWindows;
  final bool isMacOS;
  final bool isLinux;
  final bool isAndroid;
  final bool isIOS;

  const PlatformInfo({
    this.isWeb = false,
    this.isWasm = false,
    this.isWindows = false,
    this.isMacOS = false,
    this.isLinux = false,
    this.isAndroid = false,
    this.isIOS = false,
  });

  /// Reads the real host platform exactly once. `dart:io`'s [Platform] throws on
  /// web, so every native check is guarded by [kIsWeb] first.
  factory PlatformInfo.host() => PlatformInfo(
        isWeb: kIsWeb,
        isWasm: kIsWasm,
        isWindows: !kIsWeb && Platform.isWindows,
        isMacOS: !kIsWeb && Platform.isMacOS,
        isLinux: !kIsWeb && Platform.isLinux,
        isAndroid: !kIsWeb && Platform.isAndroid,
        isIOS: !kIsWeb && Platform.isIOS,
      );

  /// True on a native desktop OS (Windows/macOS/Linux); false on web and mobile.
  bool get isDesktop => isWindows || isMacOS || isLinux;
}
