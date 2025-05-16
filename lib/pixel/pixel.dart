import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';

class BleScanManager {
  final Map<String, PixelDie> _discoveredDevices = {};
  final _deviceController = StreamController<List<PixelDie>>.broadcast();

  Stream<List<PixelDie>> get deviceStream => _deviceController.stream;

  Future<bool> checkSupported() async {
    return FlutterBluePlus.isSupported;
  }

  StreamSubscription<BluetoothAdapterState> listenToStates(
    Function(BluetoothAdapterState) callback,
  ) {
    return FlutterBluePlus.adapterState.listen(callback);
  }

  Future<void> connect() async {
    await FlutterBluePlus.adapterState
        .firstWhere(
          (state) => state == BluetoothAdapterState.on,
          orElse: () => throw TimeoutException('Bluetooth did not turn on'),
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout:
              () =>
                  throw TimeoutException(
                    'Bluetooth connection timeout after 10 seconds',
                  ),
        );
  }

  Future<void> scan(Function(List<ScanResult>) foundResultHandler) async {
    var scanSub = FlutterBluePlus.onScanResults.listen(foundResultHandler);
    // Start scanning
    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: 15),
      withServices: [pixelsService], // Filter by service UUID (optional)
    );
    FlutterBluePlus.cancelWhenScanComplete(scanSub);
  }

  Future<void> scanForDevices() async {
    var scanSub = FlutterBluePlus.onScanResults.listen((srs) async {
      for (var sr in srs) {
        var dev = sr.device;
        dev.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
            _discoveredDevices.remove(dev.remoteId.str);
            _deviceController.add(List.of(_discoveredDevices.values));
            print("${dev.remoteId.str} disconnected");
          }
        });
        var die = await PixelDie.fromDevice(dev);
        _discoveredDevices.putIfAbsent(dev.remoteId.str, () => die);
        _deviceController.add(List.of(_discoveredDevices.values));
      }
    });
    // Start scanning
    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: 15),
      withServices: [pixelsService], // Filter by service UUID (optional)
    );
    FlutterBluePlus.cancelWhenScanComplete(scanSub);
  }

  // Get currently discovered devices
  Map<String, PixelDie> getDiscoveredDevices() {
    return _discoveredDevices;
  }

  // Stop scanning for devices
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // Clean up resources
  void dispose() {
    stopScan();
    _deviceController.close();
  }
}

class DiceInfo {
  final int ledCount;
  final int designAndColor;
  final int reserved;
  final int dataSetHash;
  final int pixelId;
  final int availableFlash;
  final int buildTimestamp;

  DiceInfo({
    required this.ledCount,
    required this.designAndColor,
    required this.reserved,
    required this.dataSetHash,
    required this.pixelId,
    required this.availableFlash,
    required this.buildTimestamp,
  });

  factory DiceInfo.fromJson(Map<String, dynamic> json) {
    return DiceInfo(
      ledCount: json['ledCount'] as int,
      designAndColor: json['designAndColor'] as int,
      reserved: json['reserved'] as int,
      dataSetHash: json['dataSetHash'] as int,
      pixelId: json['pixelId'] as int,
      availableFlash: json['availableFlash'] as int,
      buildTimestamp: json['buildTimestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ledCount': ledCount,
      'designAndColor': designAndColor,
      'reserved': reserved,
      'dataSetHash': dataSetHash,
      'pixelId': pixelId,
      'availableFlash': availableFlash,
      'buildTimestamp': buildTimestamp,
    };
  }
}

class DiceState {
  int? rollState;
  int? currentFaceIndex;
  int? currentFaceValue;
  int? batteryLevel;
  int? batteryState;
  DateTime? lastRolled;

  DiceState({
    this.rollState,
    this.currentFaceIndex,
    this.currentFaceValue,
    this.batteryLevel,
    this.batteryState,
    this.lastRolled,
  });

  factory DiceState.fromJson(Map<String, dynamic> json) {
    return DiceState(
      rollState: json['rollState'] as int,
      currentFaceIndex: json['currentFaceIndex'] as int,
      currentFaceValue: json['currentFaceValue'] as int,
      batteryLevel: json['batteryLevel'] as int,
      batteryState: json['batteryState'] as int,
      lastRolled: DateTime.parse(json['lastRolled'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rollState': rollState,
      'currentFaceIndex': currentFaceIndex,
      'currentFaceValue': currentFaceValue,
      'batteryLevel': batteryLevel,
      'batteryState': batteryState,
      'lastRolled': lastRolled?.toIso8601String(),
    };
  }
}

class PixelDie {
  BluetoothDevice device;
  BluetoothCharacteristic writeChar;
  BluetoothCharacteristic notifyChar;
  DiceInfo? info;
  late DiceState state;
  Map<MessageType, Function(RxMessage)> messageRxCallbacks = {};

  PixelDie({
    required this.device,
    required this.writeChar,
    required this.notifyChar,
  }) {
    state = DiceState();
    notifyChar.onValueReceived.listen(_readNotify);
    // Send IAmADie request message (0x01)
    _sendMessageBuffer(MessageWhoAreYou().toBuffer());
  }

  static Future<PixelDie> fromDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      await device.discoverServices();

      var service = device.servicesList.firstWhere(
        (bs) => bs.serviceUuid == pixelsService,
      );
      var writeChar = service.characteristics.firstWhere(
        (c) => c.uuid == pixelWriteCharacteristic,
      );
      var notifyChar = service.characteristics.firstWhere(
        (c) => c.uuid == pixelNotifyCharacteristic,
      );

      await notifyChar.setNotifyValue(true);

      return PixelDie(
        device: device,
        writeChar: writeChar,
        notifyChar: notifyChar,
      );
    } catch (e) {
      throw Exception('Failed to setup PixelDie: $e');
    }
  }

  Future<void> _sendMessageBuffer(List<int> data) async {
    try {
      await writeChar.write(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> sendMessage(TxMessage msg) async {
    await _sendMessageBuffer(msg.toBuffer());
  }

  void _readNotify(List<int> data) {
    var msgType = MessageType.values[data[0]];
    switch (msgType) {
      case MessageType.iAmADie:
        var msg = MessageIAmADie.parse(data);
        _updateStateIAmADie(msg);
        print('Received msg IAmADie: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(MessageType.iAmADie)) {
          messageRxCallbacks[MessageType.iAmADie]!(msg);
        }
        break;
      case MessageType.batteryLevel:
        var msg = MessageBatteryLevel.parse(data);
        _updateStateBattery(msg);
        print('Received msg BatteryLevel: ${json.encode(msg)}');
        if (messageRxCallbacks.containsKey(MessageType.batteryLevel)) {
          messageRxCallbacks[MessageType.batteryLevel]!(msg);
        }
        break;
      case MessageType.rollState:
        var msg = MessageRollState.parse(data);
        _updateStateRoll(msg);
        print(
          'Received msg RollState: ${RollState.values[msg.rollState]} ${json.encode(msg)}',
        );
        if (messageRxCallbacks.containsKey(MessageType.rollState)) {
          messageRxCallbacks[MessageType.rollState]!(msg);
        }
        break;
      default:
        var msg = MessageNone.parse(data);
        print('Received data: ${msg.buffer}');
        if (messageRxCallbacks.containsKey(MessageType.none)) {
          messageRxCallbacks[MessageType.none]!(msg);
        }
    }
    //
  }

  void _updateStateIAmADie(MessageIAmADie msg) {
    info ??= DiceInfo(
      ledCount: msg.ledCount,
      designAndColor: msg.designAndColor,
      reserved: msg.reserved,
      dataSetHash: msg.dataSetHash,
      pixelId: msg.pixelId,
      availableFlash: msg.availableFlash,
      buildTimestamp: msg.buildTimestamp,
    );

    state.rollState = msg.rollState;
    state.currentFaceIndex = msg.currentFaceIndex;
    state.currentFaceValue = msg.currentFaceValue;
    state.batteryLevel = msg.batteryLevel;
    state.batteryState = msg.batteryState;
  }

  void _updateStateBattery(MessageBatteryLevel msg) {
    state.batteryLevel = msg.batteryLevel;
    state.batteryState = msg.batteryState;
  }

  void _updateStateRoll(MessageRollState msg) {
    state.rollState = msg.rollState;
    state.currentFaceIndex = msg.currentFaceIndex;
    state.currentFaceValue = msg.currentFaceValue;
    state.lastRolled = DateTime.now();
  }
}
