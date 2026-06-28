import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart' as pix;
import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';

final _log = Logger('PixelDieService');

const int _kMaxChunkSize = 100;
const int _kAckTimeoutMs = 5000;

class PixelsTransferException implements Exception {
  final String message;
  const PixelsTransferException(this.message);
  @override
  String toString() => 'PixelsTransferException: $message';
}

/// Service wrapping a Pixels die (an external system reached via its SDK).
///
/// Owns the die-facing operations the app needs — flash-transfer (permanent),
/// instant-animation (RAM, preview), single-animation preview, and rename — over
/// the bulk-transfer protocol. Talks to the die through [PixelsDieInterface] so
/// a simulator can be injected in tests. Contains no business logic; the domain
/// orchestrates it.
class PixelDieService {
  final PixelsDieInterface die;

  PixelDieService(this.die);

  /// Hash of the animation set currently on the die (from the last `IAmADie`),
  /// or null if unknown. Used to tell which profile is currently flashed.
  int? get currentDataSetHash => die.currentDataSetHash;

  /// Upload [profile] to the die's flash memory (survives sleep/reboot).
  Future<void> transferProfile(PixelProfile profile) async {
    final ds = PixelDataSet(profile);
    final stats = ds.computeStats();
    final bytes = ds.toByteArray();
    final ourHash = ds.computeHash().toUnsigned(32);

    _log.info('Transferring profile "${profile.name}" (${bytes.length} bytes, '
        'hash=0x${ourHash.toRadixString(16).toUpperCase().padLeft(8, '0')}) to ${die.dieId}');
    _log.fine(
      'DataSet stats: palette=${stats.paletteSize} anims=${stats.animationCount}×${stats.animationSize}B '
      'conds=${stats.conditionCount}×${stats.conditionSize}B '
      'acts=${stats.actionCount}×${stats.actionSize}B rules=${stats.ruleCount}',
    );

    // Step 1: send header, wait for ack
    final headerMsg = pix.MessageTransferAnimationSet(
      paletteSize: stats.paletteSize,
      rgbKeyFrameCount: stats.rgbKeyFrameCount,
      rgbTrackCount: stats.rgbTrackCount,
      keyFrameCount: stats.keyFrameCount,
      trackCount: stats.trackCount,
      animationCount: stats.animationCount,
      animationSize: stats.animationSize,
      conditionCount: stats.conditionCount,
      conditionSize: stats.conditionSize,
      actionCount: stats.actionCount,
      actionSize: stats.actionSize,
      ruleCount: stats.ruleCount,
      brightness: stats.brightness,
    );

    final headerAck = await die.sendAndWaitFor<pix.MessageTransferAnimationSetAck>(
      headerMsg,
      pix.PixelMessageType.transferAnimationSetAck,
      timeout: const Duration(milliseconds: _kAckTimeoutMs),
    );

    if (!headerAck.canDownload) {
      _log.severe('Transfer rejected (result=0 = not enough memory): raw buffer=${headerAck.buffer}');
      throw PixelsTransferException('Die rejected transfer: not enough flash memory (ack result=0)');
    }

    // Register listener for finished BEFORE upload so we don't miss the event.
    final finishedFuture = die.waitFor<pix.MessageTransferAnimationSetFinished>(
      pix.PixelMessageType.transferAnimationSetFinished,
      timeout: const Duration(milliseconds: _kAckTimeoutMs),
    );

    await _uploadBulkData(bytes);
    await finishedFuture;

    _log.info('Profile transfer complete for "${profile.name}" '
        '(${bytes.length} bytes, hash=0x${ourHash.toRadixString(16).toUpperCase().padLeft(8, '0')})');

    // Verbose verification, only when debug logging is enabled: dump the exact
    // bytes sent and poll the die for its freshly-stored hash to confirm the
    // transfer landed intact (useful for byte-level comparison against the
    // official app / pixels-js fixtures).
    if (_log.isLoggable(Level.FINE)) {
      await _verifyTransfer(bytes, ourHash);
    }
  }

  /// Debug-only: logs a hex dump of the sent bytes and compares our hash against
  /// the die's actually-stored hash (read via a fresh IAmADie). The die does not
  /// proactively send IAmADie after a transfer, so we poll with WhoAreYou.
  Future<void> _verifyTransfer(Uint8List bytes, int ourHash) async {
    _log.fine('DataSet bytes (${bytes.length}) sent to ${die.dieId}:\n${_hexDump(bytes)}');

    var dieHashAfter = die.currentDataSetHash?.toUnsigned(32) ?? 0;
    try {
      final iAmADieFuture = die.waitFor<pix.MessageIAmADie>(
        pix.PixelMessageType.iAmADie,
        timeout: const Duration(milliseconds: _kAckTimeoutMs),
      );
      await die.sendMessage(pix.MessageWhoAreYou());
      final fresh = await iAmADieFuture;
      dieHashAfter = fresh.dataSetHash.toUnsigned(32);
    } catch (e) {
      _log.warning('Could not read fresh IAmADie hash after transfer: $e');
    }

    _log.fine(
      'Transfer verification: '
      'ourHash=0x${ourHash.toRadixString(16).toUpperCase().padLeft(8, '0')} '
      'dieHash=0x${dieHashAfter.toRadixString(16).toUpperCase().padLeft(8, '0')} '
      '${ourHash == dieHashAfter ? "MATCH ✓" : "MISMATCH ✗ — bytes on die differ from what we sent"}',
    );
  }

  /// Space-separated hex dump, 16 bytes per line with a byte offset prefix.
  static String _hexDump(Uint8List data) {
    final sb = StringBuffer();
    for (var i = 0; i < data.length; i += 16) {
      final end = (i + 16 < data.length) ? i + 16 : data.length;
      sb.write('${i.toRadixString(16).padLeft(4, '0')}: ');
      for (var j = i; j < end; j++) {
        sb.write(data[j].toRadixString(16).padLeft(2, '0'));
        sb.write(' ');
      }
      sb.write('\n');
    }
    return sb.toString().trimRight();
  }

  /// Upload animations to die RAM for preview (lost on sleep/reboot).
  ///
  /// If the die already has the same data (hash match), it returns immediately.
  Future<void> transferInstantAnimation(PixelProfile profile) async {
    final ds = PixelDataSet(profile);
    final stats = ds.computeInstantStats();
    final bytes = ds.toAnimationsByteArray();

    _log.info('Transferring instant animation (${bytes.length} bytes, hash=0x${stats.hash.toRadixString(16)})');

    final headerMsg = pix.MessageTransferInstantAnimationSet(
      paletteSize: stats.paletteSize,
      rgbKeyFrameCount: stats.rgbKeyFrameCount,
      rgbTrackCount: stats.rgbTrackCount,
      keyFrameCount: stats.keyFrameCount,
      trackCount: stats.trackCount,
      animationCount: stats.animationCount,
      animationSize: stats.animationSize,
      hash: stats.hash,
    );

    final ack = await die.sendAndWaitFor<pix.MessageTransferInstantAnimationSetAck>(
      headerMsg,
      pix.PixelMessageType.transferInstantAnimationSetAck,
      timeout: const Duration(milliseconds: _kAckTimeoutMs),
    );

    switch (ack.ackType) {
      case pix.TransferInstantAckType.upToDate:
        _log.info('Die already has this animation set (hash match), skipping upload');
        return;
      case pix.TransferInstantAckType.noMemory:
        throw const PixelsTransferException('Die reports not enough RAM for instant animation');
      case pix.TransferInstantAckType.download:
        break;
    }

    final finishedFuture = die.waitFor<pix.MessageTransferInstantAnimationSetFinished>(
      pix.PixelMessageType.transferInstantAnimationSetFinished,
      timeout: const Duration(milliseconds: _kAckTimeoutMs),
    );

    await _uploadBulkData(bytes);
    await finishedFuture;

    _log.info('Instant animation transfer complete');
  }

  /// Previews one animation from [profile] once, independent of the profile's
  /// rules: uploads the whole animation set to the die's instant-animation slot
  /// and plays the animation at [animIndex] a single time across all faces.
  ///
  /// The entire set is uploaded (not just the one animation) because animations
  /// can reference siblings by index — notably [PixelAnimationSequence], whose
  /// entries point at other animations in the same set. Playing in isolation
  /// would leave those references dangling.
  ///
  /// This is the one place that owns the preview convention (single-shot,
  /// `faceIndex: -1`); UI callers add only their own progress/feedback around it.
  Future<void> previewProfileAnimation(PixelProfile profile, int animIndex) async {
    await transferInstantAnimation(profile);
    await playInstantAnimation(animIndex: animIndex, faceIndex: -1, loopCount: 1);
  }

  /// Play an already-uploaded instant animation at the given index.
  Future<void> playInstantAnimation({int animIndex = 0, int faceIndex = 0, int loopCount = 1}) async {
    await die.sendMessage(pix.MessagePlayInstantAnimation(
      animIndex: animIndex,
      faceIndex: faceIndex,
      loopCount: loopCount,
    ));
  }

  /// Rename the die (max 31 chars).
  Future<void> setName(String name) async {
    await die.sendMessage(pix.MessageSetName(name));
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<void> _uploadBulkData(Uint8List data) async {
    // BulkSetup
    await die.sendAndWaitFor<pix.MessageBulkSetupAck>(
      pix.MessageBulkSetup(size: data.length),
      pix.PixelMessageType.bulkSetupAck,
      timeout: const Duration(milliseconds: _kAckTimeoutMs),
    );

    // BulkData chunks
    var offset = 0;
    var remaining = data.length;
    while (remaining > 0) {
      final chunkSize = remaining < _kMaxChunkSize ? remaining : _kMaxChunkSize;
      final chunk = data.sublist(offset, offset + chunkSize).toList();

      final ack = await die.sendAndWaitFor<pix.MessageBulkDataAck>(
        pix.MessageBulkData(size: chunkSize, offset: offset, data: chunk),
        pix.PixelMessageType.bulkDataAck,
        timeout: const Duration(milliseconds: _kAckTimeoutMs),
      );

      _log.finer('Chunk ack offset=${ack.offset}, expected=$offset');
      remaining -= chunkSize;
      offset += chunkSize;

      final progress = (100 * offset / data.length).round();
      _log.fine('Bulk upload: $progress% ($offset / ${data.length} bytes)');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PixelsDieInterface — the service's port over the die's SDK message plumbing.
// Kept here (not in core/) because it is coupled to the SDK message types
// (TxMessage/RxMessage/PixelMessageType); it is a service-layer port, not a
// clean app port. Implemented by PixelBleAdapter (real) and PixelsDieSimulator.
// ─────────────────────────────────────────────────────────────────────────────

abstract class PixelsDieInterface {
  String get dieId;

  /// Hash of the animation set currently stored on the die, as reported by the
  /// last `IAmADie` message. Returns `null` if not yet known.
  int? get currentDataSetHash;

  Future<void> sendMessage(TxMessage msg);

  Future<T> sendAndWaitFor<T extends RxMessage>(
    TxMessage msg,
    pix.PixelMessageType waitFor, {
    required Duration timeout,
  });

  Future<T> waitFor<T extends RxMessage>(
    pix.PixelMessageType type, {
    required Duration timeout,
  });
}

/// Adapts an existing [PixelDie] to [PixelsDieInterface].
class PixelBleAdapter implements PixelsDieInterface {
  final PixelDie _die;

  PixelBleAdapter(this._die);

  @override
  String get dieId => _die.dieId;

  @override
  int? get currentDataSetHash => _die.info?.dataSetHash;

  @override
  Future<void> sendMessage(TxMessage msg) => _die.sendMessage(msg);

  // Message correlation lives on the die (GenericBleDie); the adapter just maps
  // the port's PixelMessageType to the die's int-keyed API.
  @override
  Future<T> sendAndWaitFor<T extends RxMessage>(
    TxMessage msg,
    pix.PixelMessageType waitFor, {
    required Duration timeout,
  }) =>
      _die.sendAndWaitFor<T>(msg, waitFor.index, timeout: timeout);

  @override
  Future<T> waitFor<T extends RxMessage>(
    pix.PixelMessageType type, {
    required Duration timeout,
  }) =>
      _die.waitForMessage<T>(type.index, timeout: timeout);
}
