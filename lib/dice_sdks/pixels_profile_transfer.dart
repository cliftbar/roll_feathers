import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

final _log = Logger('PixelsProfileTransfer');

const int _kMaxChunkSize = 100;
const int _kAckTimeoutMs = 5000;

class PixelsTransferException implements Exception {
  final String message;
  const PixelsTransferException(this.message);
  @override
  String toString() => 'PixelsTransferException: $message';
}

/// Manages profile upload to a Pixels die via the bulk-transfer protocol.
///
/// Both flash-transfer (permanent) and instant-animation (RAM, preview) are
/// supported. Use a [PixelsDieInterface] so tests can inject a simulator.
class PixelsProfileTransfer {
  final PixelsDieInterface die;

  PixelsProfileTransfer(this.die);

  /// Upload [profile] to the die's flash memory (survives sleep/reboot).
  Future<void> transferProfile(PixelProfile profile) async {
    final ds = PixelDataSet(profile);
    final stats = ds.computeStats();
    final bytes = ds.toByteArray();

    _log.info('Transferring profile "${profile.name}" (${bytes.length} bytes) to ${die.dieId}');

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
      throw const PixelsTransferException('Die reports not enough memory for profile');
    }

    // Register listener for finished BEFORE upload so we don't miss the event.
    final finishedFuture = die.waitFor<pix.MessageTransferAnimationSetFinished>(
      pix.PixelMessageType.transferAnimationSetFinished,
      timeout: const Duration(milliseconds: _kAckTimeoutMs),
    );

    await _uploadBulkData(bytes);
    await finishedFuture;

    _log.info('Profile transfer complete');
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
// PixelsDieInterface — abstract over real BLE die and simulator
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

  @override
  Future<T> sendAndWaitFor<T extends RxMessage>(
    TxMessage msg,
    pix.PixelMessageType waitFor, {
    required Duration timeout,
  }) async {
    final completer = Completer<T>();
    final callbackKey = 'transfer_${DateTime.now().microsecondsSinceEpoch}';

    void onMsg(RxMessage m) {
      if (!completer.isCompleted) {
        completer.complete(m as T);
      }
    }

    _die.addMessageCallback(waitFor.index, callbackKey, onMsg);

    try {
      await _die.sendMessage(msg);
      return await completer.future.timeout(timeout);
    } finally {
      _die.messageRxCallbacks[waitFor.index]?.remove(callbackKey);
    }
  }

  @override
  Future<T> waitFor<T extends RxMessage>(
    pix.PixelMessageType type, {
    required Duration timeout,
  }) async {
    final completer = Completer<T>();
    final callbackKey = 'wait_${DateTime.now().microsecondsSinceEpoch}';

    void onMsg(RxMessage m) {
      if (!completer.isCompleted) {
        completer.complete(m as T);
      }
    }

    _die.addMessageCallback(type.index, callbackKey, onMsg);

    try {
      return await completer.future.timeout(timeout);
    } finally {
      _die.messageRxCallbacks[type.index]?.remove(callbackKey);
    }
  }
}
