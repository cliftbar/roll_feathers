import 'dart:async';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/godice.dart' as godice;
import 'package:roll_feathers/repositories/ble/ble_repository.dart';

/// A protocol-level simulator for a GoDice die.
///
/// Implements [BleDeviceWrapper] directly so it can be injected wherever a
/// real BLE device would be — unit tests, widget tests, and integration_test
/// alike.  No mocktail, no real Bluetooth.
///
/// The [dieType] determines which face→vector lookup table is used when
/// [rollTo] is called.
///
/// Usage:
/// ```dart
/// final sim = GoDiceDieSimulator(dieType: godice.GodiceDieType.d6);
/// final die = await GoDiceBle.create(dieFaceType: godice.GodiceDieType.d6, device: sim);
/// sim.rollTo(4);   // face 4
/// expect(die.state.currentFaceValue, 4);
/// sim.dispose();
/// ```
class GoDiceDieSimulator implements BleDeviceWrapper {
  final godice.GodiceDieType dieType;
  final String _deviceId;
  final String _friendlyName;

  @override
  bool initialized = false;

  @override
  late Logger log = Logger('GoDiceDieSimulator');

  final _notifyController =
      StreamController<List<int>>.broadcast(sync: true);

  /// All [writeMessage] payloads the app sent to this simulated die, in order.
  final List<List<int>> writtenMessages = [];

  GoDiceDieSimulator({
    this.dieType = godice.GodiceDieType.d6,
    String deviceId = 'sim-godice-01',
    String friendlyName = 'Simulated GoDice',
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
  List<String> get servicesUuids => [godice.godiceServiceGuid];

  @override
  List<String> get characteristicUuids =>
      [godice.godiceWriteCharacteristic, godice.godiceNotifyCharacteristic];

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

  /// Simulate the die starting to roll (shake/move state).
  void setRolling() {
    _emit(godice.MessageRollStart.dataToBuffer());
  }

  /// Simulate a completed roll landing on [faceValue] (1-based).
  ///
  /// Looks up the canonical gravity vector for [faceValue] in the GoDice
  /// vector table for [dieType] and emits a `MessageStable` packet, which
  /// is what the real die sends when it settles.
  ///
  /// Throws [ArgumentError] if [faceValue] is not valid for the die type.
  void rollTo(int faceValue, {godice.GodiceDieType? overrideDieType}) {
    final type = overrideDieType ?? dieType;
    final faceVectors = godice.vectors[type];
    if (faceVectors == null || !faceVectors.containsKey(faceValue)) {
      throw ArgumentError(
        'faceValue $faceValue is not valid for die type $type. '
        'Valid values: ${faceVectors?.keys.toList() ?? "none (unknown die type)"}',
      );
    }
    _emit(godice.MessageStable.dataToBuffer(faceVectors[faceValue]!));
  }

  /// Simulate a battery level acknowledgment from the die.
  void setBattery(int percent) {
    _emit(godice.MessageBatteryLevelAck.dataToBuffer(percent.clamp(0, 100)));
  }

  void dispose() {
    if (!_notifyController.isClosed) _notifyController.close();
  }

  void _emit(List<int> packet) {
    if (!_notifyController.isClosed) _notifyController.add(packet);
  }
}
