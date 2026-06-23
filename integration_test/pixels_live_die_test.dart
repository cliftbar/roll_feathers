// Run with a Pixels die nearby:
//   flutter test integration_test/pixels_live_die_test.dart -d macos
//
// These tests require real BLE hardware and are intentionally excluded from
// all_tests.dart.  They skip gracefully when no die is found.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_builtin_profiles.dart';
import 'package:roll_feathers/dice_sdks/pixels_patterns.dart';
import 'package:roll_feathers/dice_sdks/pixels_profile_transfer.dart';
import 'package:roll_feathers/repositories/ble/ble_universal_repository.dart';

// ─── timeouts ────────────────────────────────────────────────────────────────

const _kBleReadyTimeout = Duration(seconds: 5);
const _kScanTimeout = Duration(seconds: 15);
const _kConnectTimeout = Duration(seconds: 10);
const _kResponseTimeout = Duration(seconds: 5);
const _kTransferTimeout = Duration(seconds: 60);

// ─── helpers ─────────────────────────────────────────────────────────────────

/// Wait for BLE adapter to be powered on. Returns false if not available.
Future<bool> _waitForBle() async {
  try {
    final state = await UniversalBle.availabilityStream
        .firstWhere(
          (s) =>
              s == AvailabilityState.poweredOn ||
              s == AvailabilityState.poweredOff ||
              s == AvailabilityState.unsupported,
        )
        .timeout(_kBleReadyTimeout);
    return state == AvailabilityState.poweredOn;
  } on TimeoutException {
    return false;
  }
}

/// Scan for the first Pixels die in range. Returns null if none found.
Future<BleDevice?> _scanForPixelsDie() async {
  final completer = Completer<BleDevice>();
  StreamSubscription<BleDevice>? sub;

  sub = UniversalBle.scanStream.listen((device) {
    if (!completer.isCompleted) {
      completer.complete(device);
    }
  });

  await UniversalBle.startScan(
    scanFilter: ScanFilter(withServices: [pix.pixelsService]),
  );

  BleDevice? found;
  try {
    found = await completer.future.timeout(_kScanTimeout);
  } on TimeoutException {
    // no die found — skip
  } finally {
    await sub.cancel();
    await UniversalBle.stopScan();
  }
  return found;
}

/// Connect, discover services, and initialise a [PixelDie].
/// The caller owns disconnecting the device afterward.
Future<PixelDie> _connectDie(BleDevice device) async {
  await UniversalBle.connect(device.deviceId).timeout(_kConnectTimeout);
  final wrapper = UniversalBleDevice(device: device);
  final die = await GenericBleDie.fromDevice(wrapper) as PixelDie;
  return die;
}

/// Request IAmADie and wait for the response.
Future<pix.MessageIAmADie> _whoAreYou(
  PixelDie die,
  PixelBleAdapter adapter,
) async {
  final future = adapter.waitFor<pix.MessageIAmADie>(
    pix.PixelMessageType.iAmADie,
    timeout: _kResponseTimeout,
  );
  await die.sendMessage(pix.MessageWhoAreYou());
  return future;
}

// ─── tests ───────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) => debugPrint('[${r.loggerName}] ${r.message}'));

  PixelDie? die;

  setUp(() async {
    registerBuiltinPatterns(kBuiltinPatterns);
    UniversalBle.timeout = const Duration(seconds: 25);
    if (!await _waitForBle()) {
      // BLE state will cause individual tests to skip
    }
  });

  tearDown(() async {
    die?.dispose();
    if (die != null) {
      try {
        await UniversalBle.disconnect(die!.dieId);
      } catch (_) {}
      die = null;
    }
  });

  // ---------------------------------------------------------------------------
  // 1 — Connectivity smoke-test
  // ---------------------------------------------------------------------------

  test('scan, connect, receive IAmADie', () async {
    if (!await _waitForBle()) {
      debugPrint('[live-die] SKIP: BLE not available');
      return;
    }

    final device = await _scanForPixelsDie();
    if (device == null) {
      debugPrint('[live-die] SKIP: no Pixels die found');
      return;
    }
    debugPrint('[live-die] found: ${device.name ?? device.deviceId}');

    die = await _connectDie(device);
    final adapter = PixelBleAdapter(die!);
    final info = await _whoAreYou(die!, adapter);

    debugPrint(
      '[live-die] IAmADie: type=${info.pixelDieTypeFaces} '
      'leds=${info.ledCount} '
      'hash=0x${info.dataSetHash.toUnsigned(32).toRadixString(16).padLeft(8, '0')}',
    );

    // Sanity checks — any connected Pixels die should pass these
    expect(info.ledCount, greaterThan(0));
    expect(info.pixelDieTypeFaces, isNot(pix.PixelDieType.unknown));
  });

  // ---------------------------------------------------------------------------
  // 2 — Hash parity: flash a built-in profile and verify dataSetHash
  // ---------------------------------------------------------------------------

  for (final profileName in [
    'Default Profile',
    'Waterfall',
    'Fountain',
    'Spiral',
    'Noise',
    'Rose',
    'Fire',
    'Magic',
    'Water',
  ]) {
    test('flash "$profileName" → dataSetHash matches Dart computation', () async {
      if (!await _waitForBle()) {
        debugPrint('[live-die] SKIP: BLE not available');
        return;
      }

      final device = await _scanForPixelsDie();
      if (device == null) {
        debugPrint('[live-die] SKIP: no Pixels die found');
        return;
      }

      die = await _connectDie(device);
      final adapter = PixelBleAdapter(die!);

      // Wait for the initial IAmADie (sent by _init via WhoAreYou) to settle.
      final initialInfo = await _whoAreYou(die!, adapter);
      debugPrint(
        '[live-die] connected: rollState=${initialInfo.rollState} '
        'flash=${initialInfo.availableFlash} '
        'hash=0x${initialInfo.dataSetHash.toUnsigned(32).toRadixString(16).padLeft(8, '0')}',
      );

      final preset = kBuiltinProfiles.firstWhere((p) => p.name == profileName);
      final profile = preset.build();
      final expectedHash = PixelDataSet(profile).computeHash().toUnsigned(32);

      debugPrint(
        '[live-die] transferring "$profileName" '
        '(expected hash=0x${expectedHash.toRadixString(16).padLeft(8, '0')})',
      );

      final transfer = PixelsProfileTransfer(adapter);
      await transfer.transferProfile(profile).timeout(_kTransferTimeout);

      // Flash is done — actively request IAmADie to read the updated hash.
      // We don't rely on the spontaneous broadcast the die may send during transfer.
      await Future.delayed(const Duration(milliseconds: 200));
      final postInfo = await _whoAreYou(die!, adapter);

      final actualHash = postInfo.dataSetHash.toUnsigned(32);
      debugPrint(
        '[live-die] post-flash hash=0x${actualHash.toRadixString(16).padLeft(8, '0')} '
        '(${actualHash == expectedHash ? 'MATCH' : 'MISMATCH'})',
      );

      expect(actualHash, expectedHash);
    });
  }

  // ---------------------------------------------------------------------------
  // 3 — Instant animation: preview without flashing
  // ---------------------------------------------------------------------------

  test('instant animation transfer and play (visual check)', () async {
    if (!await _waitForBle()) {
      debugPrint('[live-die] SKIP: BLE not available');
      return;
    }

    final device = await _scanForPixelsDie();
    if (device == null) {
      debugPrint('[live-die] SKIP: no Pixels die found');
      return;
    }

    die = await _connectDie(device);
    final adapter = PixelBleAdapter(die!);

    // Use a simple single-color rainbow as the instant preview
    final profile = kBuiltinProfiles.firstWhere((p) => p.name == 'Rainbow').build();
    final transfer = PixelsProfileTransfer(adapter);

    // Should not throw
    await expectLater(
      transfer.transferInstantAnimation(profile).timeout(_kTransferTimeout),
      completes,
    );

    // Play anim index 0 on face 19 (top) once
    await transfer.playInstantAnimation(animIndex: 0, faceIndex: 19, loopCount: 1);
    debugPrint('[live-die] instant animation sent — verify visually that die lit up');
  });

  // ---------------------------------------------------------------------------
  // 4 — Pattern-based animations: Keyframed and GradientPattern hash parity
  // ---------------------------------------------------------------------------

  test('Keyframed animation with builtin pattern — dataSetHash matches', () async {
    if (!await _waitForBle()) {
      debugPrint('[live-die] SKIP: BLE not available');
      return;
    }
    final device = await _scanForPixelsDie();
    if (device == null) {
      debugPrint('[live-die] SKIP: no Pixels die found');
      return;
    }

    die = await _connectDie(device);
    final adapter = PixelBleAdapter(die!);
    await _whoAreYou(die!, adapter);

    final pattern = kBuiltinPatterns.first;
    final profile = PixelProfile(
      id: '',
      name: 'Keyframed Test',
      brightness: 255,
      animations: [
        PixelAnimationKeyframed(durationMs: 2000, pattern: pattern),
      ],
      rules: [
        PixelRule(
          condition: PixelConditionRolled(),
          actions: [PixelActionPlayAnimation(animIndex: 0)],
        ),
      ],
    );
    final expectedHash = PixelDataSet(profile).computeHash().toUnsigned(32);
    debugPrint(
      '[live-die] transferring Keyframed (pattern="${pattern.name}") '
      'hash=0x${expectedHash.toRadixString(16).padLeft(8, '0')}',
    );

    final transfer = PixelsProfileTransfer(adapter);
    await transfer.transferProfile(profile).timeout(_kTransferTimeout);

    await Future.delayed(const Duration(milliseconds: 200));
    final postInfo = await _whoAreYou(die!, adapter);
    final actualHash = postInfo.dataSetHash.toUnsigned(32);
    debugPrint(
      '[live-die] post-flash hash=0x${actualHash.toRadixString(16).padLeft(8, '0')} '
      '(${actualHash == expectedHash ? 'MATCH' : 'MISMATCH'})',
    );
    expect(actualHash, expectedHash);
  });

  test('GradientPattern animation with builtin pattern — dataSetHash matches', () async {
    if (!await _waitForBle()) {
      debugPrint('[live-die] SKIP: BLE not available');
      return;
    }
    final device = await _scanForPixelsDie();
    if (device == null) {
      debugPrint('[live-die] SKIP: no Pixels die found');
      return;
    }

    die = await _connectDie(device);
    final adapter = PixelBleAdapter(die!);
    await _whoAreYou(die!, adapter);

    final pattern = kBuiltinPatterns.first;
    final profile = PixelProfile(
      id: '',
      name: 'GradientPattern Test',
      brightness: 255,
      animations: [
        PixelAnimationGradientPattern(
          durationMs: 2000,
          pattern: pattern,
          gradient: PixelGradient.rainbow,
        ),
      ],
      rules: [
        PixelRule(
          condition: PixelConditionRolled(),
          actions: [PixelActionPlayAnimation(animIndex: 0)],
        ),
      ],
    );
    final expectedHash = PixelDataSet(profile).computeHash().toUnsigned(32);
    debugPrint(
      '[live-die] transferring GradientPattern (pattern="${pattern.name}") '
      'hash=0x${expectedHash.toRadixString(16).padLeft(8, '0')}',
    );

    final transfer = PixelsProfileTransfer(adapter);
    await transfer.transferProfile(profile).timeout(_kTransferTimeout);

    await Future.delayed(const Duration(milliseconds: 200));
    final postInfo = await _whoAreYou(die!, adapter);
    final actualHash = postInfo.dataSetHash.toUnsigned(32);
    debugPrint(
      '[live-die] post-flash hash=0x${actualHash.toRadixString(16).padLeft(8, '0')} '
      '(${actualHash == expectedHash ? 'MATCH' : 'MISMATCH'})',
    );
    expect(actualHash, expectedHash);
  });

  // ---------------------------------------------------------------------------
  // 5 — True BLE rename: SetName is accepted (SetNameAck) and persisted
  // ---------------------------------------------------------------------------

  test('SetName renames die (SetNameAck) and restores original name', () async {
    if (!await _waitForBle()) {
      debugPrint('[live-die] SKIP: BLE not available');
      return;
    }
    final device = await _scanForPixelsDie();
    if (device == null) {
      debugPrint('[live-die] SKIP: no Pixels die found');
      return;
    }

    die = await _connectDie(device);
    final adapter = PixelBleAdapter(die!);
    await _whoAreYou(die!, adapter);

    // Capture the current advertised name so we can restore it — SetName writes
    // to the die's persistent flash settings, so this test must not leave the
    // user's die renamed.
    final originalName = (device.name?.isNotEmpty ?? false) ? device.name! : die!.friendlyName;
    debugPrint('[live-die] original name: "$originalName"');

    // Rename to a test value and wait for the firmware's SetNameAck.
    const testName = 'RollFeathersIT';
    final ack = adapter.waitFor<pix.MessageNone>(
      pix.PixelMessageType.setNameAck,
      timeout: _kResponseTimeout,
    );
    await die!.sendMessage(pix.MessageSetName(testName));
    await expectLater(ack, completes);
    debugPrint('[live-die] rename to "$testName" acked');

    // Restore the original name (also verifies a second rename round-trips).
    expect(originalName, isNotEmpty,
        reason: 'need the original name to restore the die');
    final restoreAck = adapter.waitFor<pix.MessageNone>(
      pix.PixelMessageType.setNameAck,
      timeout: _kResponseTimeout,
    );
    await die!.sendMessage(pix.MessageSetName(originalName));
    await restoreAck;
    debugPrint('[live-die] restored original name "$originalName"');
  });
}
