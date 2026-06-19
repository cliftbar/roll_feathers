import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/message_sdk.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_profile_transfer.dart';

final _log = Logger('PixelsDieSimulator');

/// In-memory simulator that speaks the Pixels BLE message protocol.
///
/// Used in tests and as a preview target when no real die is connected.
/// Implements [PixelsDieInterface] so it can be swapped in for a real die.
class PixelsDieSimulator implements PixelsDieInterface {
  @override
  final String dieId;

  @override
  int? get currentDataSetHash => _flashProfileHash;

  int? _flashProfileHash;

  final pix.PixelDieType dieType;
  final int ledCount;
  String _name;

  // Protocol state
  int rollState = 0;
  int currentFace = 0;

  // Currently stored profiles
  Uint8List? _flashProfile;
  Uint8List? _instantAnimations;

  // Bulk receive buffer
  int _expectedBulkSize = 0;
  List<int>? _bulkBuffer;
  _BulkContext? _pendingBulk;

  // LED colors (for visual preview)
  final List<int> ledColors;

  final StreamController<List<int>> _notifyController = StreamController.broadcast();

  Stream<List<int>> get notifyStream => _notifyController.stream;

  PixelsDieSimulator({
    String? dieId,
    this.dieType = pix.PixelDieType.d20,
    this.ledCount = 20,
    String? name,
  })  : dieId = dieId ?? 'sim-${DateTime.now().microsecondsSinceEpoch}',
        _name = name ?? 'Simulator',
        ledColors = List.filled(ledCount, 0xFFFFFFFF);

  String get name => _name;

  /// The last profile written to simulated flash memory (null until first transfer).
  Uint8List? get flashProfileBytes => _flashProfile;

  /// The last instant animation set written to simulated RAM (null until first transfer).
  Uint8List? get instantAnimationBytes => _instantAnimations;

  // ─── PixelsDieInterface ─────────────────────────────────────────────────────

  @override
  Future<void> sendMessage(TxMessage msg) async {
    _handleIncoming(msg.toBuffer());
  }

  @override
  Future<T> sendAndWaitFor<T extends RxMessage>(
    TxMessage msg,
    pix.PixelMessageType waitFor, {
    required Duration timeout,
  }) async {
    final completer = Completer<T>();

    late StreamSubscription<List<int>> sub;
    sub = notifyStream.listen((data) {
      if (data.isNotEmpty && data[0] == waitFor.index && !completer.isCompleted) {
        final parsed = _parseRx(data);
        if (parsed is T) {
          completer.complete(parsed);
          sub.cancel();
        }
      }
    });

    _handleIncoming(msg.toBuffer());

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        throw TimeoutException('Simulator timed out waiting for ${waitFor.name}', timeout);
      });
    } catch (_) {
      sub.cancel();
      rethrow;
    }
  }

  @override
  Future<T> waitFor<T extends RxMessage>(
    pix.PixelMessageType type, {
    required Duration timeout,
  }) async {
    final completer = Completer<T>();

    late StreamSubscription<List<int>> sub;
    sub = notifyStream.listen((data) {
      if (data.isNotEmpty && data[0] == type.index && !completer.isCompleted) {
        final parsed = _parseRx(data);
        if (parsed is T) {
          completer.complete(parsed);
          sub.cancel();
        }
      }
    });

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        throw TimeoutException('Simulator timed out waiting for ${type.name}', timeout);
      });
    } catch (_) {
      sub.cancel();
      rethrow;
    }
  }

  // ─── Simulation controls ────────────────────────────────────────────────────

  /// Simulate the die being rolled and landing on [faceIndex] (0-based).
  void simulateRoll({required int faceIndex}) {
    currentFace = faceIndex;
    rollState = 3; // rolling
    _emit(_buildRollState(3, faceIndex));

    Future.delayed(const Duration(milliseconds: 100), () {
      rollState = 1; // rolled
      _emit(_buildRollState(1, faceIndex));
    });
  }

  /// Simulate the die being picked up.
  void simulateHandling() {
    rollState = 2; // handling
    _emit(_buildRollState(2, currentFace));
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  void _handleIncoming(List<int> data) {
    if (data.isEmpty) return;
    final msgType = pix.PixelMessageType.values[data[0]];

    _log.finer('SIM recv ${msgType.name} (${data.length} bytes)');

    switch (msgType) {
      case pix.PixelMessageType.whoAreYou:
        _emit(_buildIAmADie());

      case pix.PixelMessageType.transferAnimationSet:
        final paletteSize = _getU16(data, 1);
        final animCount = _getU16(data, 11);
        // Compute total data size for this transfer
        // (We just accept and proceed)
        _pendingBulk = _BulkContext(type: _BulkType.profile);
        _emit([pix.PixelMessageType.transferAnimationSetAck.index, 0]); // result=0 → download

      case pix.PixelMessageType.transferInstantAnimationSet:
        final hash = _getU32(data, 15);
        _pendingBulk = _BulkContext(type: _BulkType.instant, hash: hash);
        _emit([pix.PixelMessageType.transferInstantAnimationSetAck.index, 0]); // download

      case pix.PixelMessageType.bulkSetup:
        final size = _getU16(data, 1);
        _expectedBulkSize = size;
        _bulkBuffer = [];
        _emit([pix.PixelMessageType.bulkSetupAck.index]);

      case pix.PixelMessageType.bulkData:
        final size = data[1];
        final offset = _getU16(data, 2);
        final chunk = data.sublist(4, 4 + size);
        _bulkBuffer?.addAll(chunk);
        // ACK with next expected offset
        _emitBulkDataAck(offset + size);

        if (_bulkBuffer != null && _bulkBuffer!.length >= _expectedBulkSize) {
          _finalizeBulkTransfer();
        }

      case pix.PixelMessageType.setName:
        final nameBytes = data.sublist(1);
        final nullIdx = nameBytes.indexOf(0);
        _name = String.fromCharCodes(nullIdx >= 0 ? nameBytes.sublist(0, nullIdx) : nameBytes);
        _log.info('SIM: name set to "$_name"');
        _emit([pix.PixelMessageType.setNameAck.index]);

      case pix.PixelMessageType.blink:
        _log.fine('SIM: blink received');
        _emit([pix.PixelMessageType.blinkAck.index]);

      case pix.PixelMessageType.stopAllAnimations:
        _log.fine('SIM: stopAllAnimations');

      case pix.PixelMessageType.playInstantAnimation:
        _log.fine('SIM: playInstantAnimation index=${data.length > 1 ? data[1] : 0}');

      case pix.PixelMessageType.requestRollState:
        _emit(_buildRollState(rollState, currentFace));

      case pix.PixelMessageType.notifyUserAck:
        _log.fine('SIM: notifyUserAck');

      default:
        _log.finer('SIM: unhandled ${msgType.name}');
    }
  }

  void _finalizeBulkTransfer() {
    final bytes = Uint8List.fromList(_bulkBuffer!);
    switch (_pendingBulk?.type) {
      case _BulkType.profile:
        _flashProfile = bytes;
        _flashProfileHash = pixelsBernsteinHash(bytes);
        _log.info('SIM: flash profile stored (${bytes.length} bytes)');
        Future.microtask(() => _emit([pix.PixelMessageType.transferAnimationSetFinished.index]));
      case _BulkType.instant:
        _instantAnimations = bytes;
        _log.info('SIM: instant animations stored (${bytes.length} bytes)');
        Future.microtask(() => _emit([pix.PixelMessageType.transferInstantAnimationSetFinished.index]));
      case null:
        _log.warning('SIM: bulk transfer completed with no pending context');
    }
    _bulkBuffer = null;
    _pendingBulk = null;
  }

  void _emit(List<int> data) {
    if (!_notifyController.isClosed) {
      _notifyController.add(data);
    }
  }

  void _emitBulkDataAck(int nextOffset) {
    _emit([
      pix.PixelMessageType.bulkDataAck.index,
      nextOffset & 0xFF,
      (nextOffset >> 8) & 0xFF,
    ]);
  }

  List<int> _buildIAmADie() {
    // Legacy flat format (matches existing roll_feathers parser)
    final buf = List<int>.filled(22, 0);
    buf[0] = pix.PixelMessageType.iAmADie.index;
    buf[1] = ledCount;
    buf[2] = 0; // designAndColor = unknown
    buf[3] = dieType.index;
    _setU32(buf, 4, 0); // dataSetHash
    _setU32(buf, 8, dieId.hashCode); // pixelId
    _setU16(buf, 12, 1024); // availableFlash
    _setU32(buf, 14, 0); // buildTimestamp
    buf[18] = rollState;
    buf[19] = currentFace;
    buf[20] = 100; // batteryLevel
    buf[21] = 0; // batteryState OK
    return buf;
  }

  List<int> _buildRollState(int state, int face) => [
    pix.PixelMessageType.rollState.index,
    state,
    face,
  ];

  RxMessage _parseRx(List<int> data) {
    if (data.isEmpty) return pix.MessageNone(buffer: data);
    final type = pix.PixelMessageType.values[data[0]];
    return switch (type) {
      pix.PixelMessageType.iAmADie => pix.MessageIAmADie.parse(data),
      pix.PixelMessageType.batteryLevel => pix.MessageBatteryLevel.parse(data),
      pix.PixelMessageType.rollState => pix.MessageRollState.parse(data),
      pix.PixelMessageType.transferAnimationSetAck =>
        pix.MessageTransferAnimationSetAck.parse(data),
      pix.PixelMessageType.transferAnimationSetFinished =>
        pix.MessageTransferAnimationSetFinished.parse(data),
      pix.PixelMessageType.bulkSetupAck => pix.MessageBulkSetupAck.parse(data),
      pix.PixelMessageType.bulkDataAck => pix.MessageBulkDataAck.parse(data),
      pix.PixelMessageType.transferInstantAnimationSetAck =>
        pix.MessageTransferInstantAnimationSetAck.parse(data),
      pix.PixelMessageType.transferInstantAnimationSetFinished =>
        pix.MessageTransferInstantAnimationSetFinished.parse(data),
      _ => pix.MessageNone(buffer: data),
    };
  }

  static int _getU16(List<int> data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  static int _getU32(List<int> data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);

  static void _setU16(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
  }

  static void _setU32(List<int> buf, int offset, int value) {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
  }

  void dispose() => _notifyController.close();
}

enum _BulkType { profile, instant }

class _BulkContext {
  final _BulkType type;
  final int hash;
  _BulkContext({required this.type, this.hash = 0});
}
