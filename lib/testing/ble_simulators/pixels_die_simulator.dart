import 'dart:async';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/repositories/ble/ble_repository.dart';

/// A protocol-level simulator for a Pixels die.
///
/// Implements [BleDeviceWrapper] directly so it can be injected wherever a
/// real BLE device would be — unit tests, widget tests, and integration_test
/// alike.  No mocktail, no real Bluetooth.
///
/// Usage:
/// ```dart
/// final sim = PixelsDieSimulator(dieType: pix.PixelDieType.d20);
/// final die = await PixelDie.create(device: sim);
/// sim.identify();          // sends iAmADie so the die knows its own type
/// sim.rollTo(17);          // rolling → rolled with face 17
/// expect(die.state.currentFaceValue, 17);
/// sim.dispose();
/// ```
class PixelsDieSimulator implements BleDeviceWrapper {
  final pix.PixelDieType dieType;
  final String _deviceId;
  final String _friendlyName;

  @override
  bool initialized = false;

  @override
  late Logger log = Logger('PixelsDieSimulator');

  final _notifyController =
      StreamController<List<int>>.broadcast(sync: true);

  /// All [writeMessage] payloads the app sent to this simulated die, in order.
  final List<List<int>> writtenMessages = [];

  PixelsDieSimulator({
    this.dieType = pix.PixelDieType.d20,
    String deviceId = 'sim-pixels-01',
    String friendlyName = 'Simulated Pixels',
  })  : _deviceId = deviceId,
        _friendlyName = friendlyName;

  // ---------------------------------------------------------------------------
  // BleDeviceWrapper interface
  // ---------------------------------------------------------------------------

  @override
  String get deviceId => _deviceId;

  @override
  String get friendlyName => _friendlyName;

  @override
  List<String> get servicesUuids => [pix.pixelsService];

  @override
  List<String> get characteristicUuids =>
      [pix.pixelWriteCharacteristic, pix.pixelNotifyCharacteristic];

  @override
  Future<bool> init() async {
    initialized = true;
    return true;
  }

  @override
  Future<void> discoverServices() async {}

  @override
  Future<void> setDeviceUuids({
    required String serviceUuid,
    required String notifyUuid,
    required String writeUuid,
  }) async {}

  @override
  Future<void> writeMessage(List<int> data) async {
    writtenMessages.add(List<int>.from(data));
  }

  @override
  Stream<List<int>> get notifyStream => _notifyController.stream;

  @override
  Future<void> disconnect() async {
    _notifyController.close();
  }

  // ---------------------------------------------------------------------------
  // Simulator actions — push protocol packets into the notify stream
  // ---------------------------------------------------------------------------

  /// Push an `iAmADie` response so the app knows the die's type and initial
  /// state.  Call this right after [PixelDie.create] to complete the
  /// handshake.
  void identify({
    int battery = 100,
    int ledCount = 20,
    DiceRollState rollState = DiceRollState.onFace,
    int faceValue = 1,
  }) {
    final faceIndex = faceValue - 1;
    _emit([
      pix.PixelMessageType.iAmADie.index,
      ledCount,
      pix.PixelDesignAndColor.onyxBlack.index,
      dieType.index,
      1, 0, 0, 0, // dataSetHash
      2, 0, 0, 0, // pixelId
      3, 0,       // availableFlash
      4, 0, 0, 0, // buildTimestamp
      rollState.index,
      faceIndex,
      battery,
      BatteryState.ok.index,
    ]);
  }

  /// Simulate the die entering the rolling state (shaking).
  void setRolling() {
    _emit([
      pix.PixelMessageType.rollState.index,
      DiceRollState.rolling.index,
      0,
    ]);
  }

  /// Simulate a completed roll landing on [faceValue] (1-based).
  /// Emits a `rolling` packet followed by a `rolled` packet, matching
  /// the real die's behaviour.
  void rollTo(int faceValue) {
    assert(faceValue >= 1, 'faceValue must be ≥ 1');
    final faceIndex = faceValue - 1;
    _emit([
      pix.PixelMessageType.rollState.index,
      DiceRollState.rolling.index,
      faceIndex,
    ]);
    _emit([
      pix.PixelMessageType.rollState.index,
      DiceRollState.rolled.index,
      faceIndex,
    ]);
  }

  /// Simulate a battery status update.
  void setBattery(int percent, {BatteryState state = BatteryState.ok}) {
    _emit([
      pix.PixelMessageType.batteryLevel.index,
      percent.clamp(0, 100),
      state.index,
    ]);
  }

  void dispose() {
    if (!_notifyController.isClosed) _notifyController.close();
  }

  void _emit(List<int> packet) {
    if (!_notifyController.isClosed) _notifyController.add(packet);
  }
}
