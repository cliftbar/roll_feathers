import 'dart:async';

import 'package:logging/logging.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/pixels.dart' as pix;
import 'package:roll_feathers/repositories/ble/ble_repository.dart';

/// BLE-device-layer simulator for a Pixels die.
///
/// Implements [BleDeviceWrapper] so it can be injected wherever a real BLE
/// device is expected — specifically for testing [PixelDie] itself (roll
/// callbacks, battery updates, state parsing) without Bluetooth hardware.
///
/// This simulator auto-responds to the handshake messages that [PixelDie]
/// sends during initialisation and normal operation. Everything else is
/// silently captured in [writtenMessages] for assertion in tests.
///
/// For testing [PixelDieService] (the higher-level bulk-transfer
/// layer), use [PixelsDieSimulator] instead.
///
/// Usage:
/// ```dart
/// final sim = PixelsBleDeviceSimulator(dieType: pix.PixelDieType.d20);
/// final die = await PixelDie.create(device: sim);
/// sim.identify(faceValue: 5, battery: 80);
/// sim.rollTo(17);
/// expect(die.state.currentFaceValue, 17);
/// sim.dispose();
/// ```
class PixelsBleDeviceSimulator implements BleDeviceWrapper {
  final pix.PixelDieType dieType;
  final String _deviceId;
  final String _friendlyName;

  @override
  bool initialized = false;

  @override
  late Logger log = Logger('PixelsBleDeviceSimulator');

  final _notifyController =
      StreamController<List<int>>.broadcast(sync: true);

  /// All [writeMessage] payloads the app sent to this simulated die, in order.
  final List<List<int>> writtenMessages = [];

  // Internal die state — kept in sync by the simulator action methods so
  // auto-responses to requestRollState / requestBatteryLevel stay accurate.
  int _faceIndex = 0;
  int _batteryPercent = 100;
  int _rollStateIndex = DiceRollState.onFace.index;
  int _batteryStateIndex = BatteryState.ok.index;

  PixelsBleDeviceSimulator({
    this.dieType = pix.PixelDieType.d20,
    String deviceId = 'sim-pixels-ble-01',
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
    if (data.isEmpty) return;
    final msgType = pix.PixelMessageType.values[data[0]];
    switch (msgType) {
      case pix.PixelMessageType.whoAreYou:
        _emit(_buildIAmADie());
      case pix.PixelMessageType.requestRollState:
        _emit(_buildRollState());
      case pix.PixelMessageType.requestBatteryLevel:
        _emit(_buildBatteryLevel());
      default:
        break;
    }
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

  /// Push a full [iAmADie] packet, updating internal state to match.
  ///
  /// Call this right after [PixelDie.create] if you need the die to
  /// advertise specific parameters (face, battery) before the tests run.
  void identify({
    int faceValue = 1,
    int battery = 100,
    BatteryState batteryState = BatteryState.ok,
    DiceRollState rollState = DiceRollState.onFace,
  }) {
    _faceIndex = faceValue - 1;
    _batteryPercent = battery;
    _rollStateIndex = rollState.index;
    _batteryStateIndex = batteryState.index;
    _emit(_buildIAmADie());
  }

  /// Simulate the die entering the rolling state (shaking).
  void setRolling() {
    _rollStateIndex = DiceRollState.rolling.index;
    _emit(_buildRollState());
  }

  /// Simulate a completed roll landing on [faceValue] (1-based).
  ///
  /// Emits a `rolling` packet followed by a `rolled` packet, matching
  /// the real die's sequence.
  void rollTo(int faceValue) {
    assert(faceValue >= 1, 'faceValue must be ≥ 1');
    _faceIndex = faceValue - 1;
    _rollStateIndex = DiceRollState.rolling.index;
    _emit(_buildRollState());
    _rollStateIndex = DiceRollState.rolled.index;
    _emit(_buildRollState());
  }

  /// Simulate a battery status update pushed from the die.
  void setBattery(int percent, {BatteryState state = BatteryState.ok}) {
    _batteryPercent = percent.clamp(0, 100);
    _batteryStateIndex = state.index;
    _emit(_buildBatteryLevel());
  }

  void dispose() {
    if (!_notifyController.isClosed) _notifyController.close();
  }

  // ---------------------------------------------------------------------------
  // Packet builders
  // ---------------------------------------------------------------------------

  List<int> _buildIAmADie() => [
    pix.PixelMessageType.iAmADie.index,
    20, // ledCount
    pix.PixelDesignAndColor.onyxBlack.index,
    dieType.index,
    1, 0, 0, 0, // dataSetHash (little-endian, fixed stub)
    2, 0, 0, 0, // pixelId
    3, 0,       // availableFlash
    4, 0, 0, 0, // buildTimestamp
    _rollStateIndex,
    _faceIndex,
    _batteryPercent,
    _batteryStateIndex,
  ];

  List<int> _buildRollState() => [
    pix.PixelMessageType.rollState.index,
    _rollStateIndex,
    _faceIndex,
  ];

  List<int> _buildBatteryLevel() => [
    pix.PixelMessageType.batteryLevel.index,
    _batteryPercent,
    _batteryStateIndex,
  ];

  void _emit(List<int> packet) {
    if (!_notifyController.isClosed) _notifyController.add(packet);
  }
}
