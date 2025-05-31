// godice_ai.dart - A Dart SDK for GoDice
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Die types
enum DieType {
  d6, // Regular 6-sided die
  d20, // 20-sided die
  d12, // 12-sided die
  d10, // 10-sided die
  d10X, // 10-sided percentile die (00-90)
  d8, // 8-sided die
  d4, // 4-sided die
  d7, // 7-sided die
  dF, // Fudge die
  custom, // Custom die
}

// Die colors
enum DieColor { black, red, green, blue, yellow, orange, purple, unknown }

// Die events
enum DieEvent { connection, batteryLevel, dieType, rollStart, stableRoll, tiltMove, fakeRoll, dieState, color }

class GoDice {
  // GoDice service and characteristic UUIDs
  static Guid SERVICE_UUID = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
  static Guid TX_CHARACTERISTIC_UUID = Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
  static Guid RX_CHARACTERISTIC_UUID = Guid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");


  // Die message types
  static const int _MSG_TYPE_GLOBAL_PARAM = 0x0A;
  static const int _MSG_TYPE_SENSOR_REQUEST = 0x0B;
  static const int _MSG_TYPE_LED_CONFIG = 0x0C;
  static const int _MSG_TYPE_STABLE_FACE = 0x0D;
  static const int _MSG_TYPE_NOTIFICATION = 0x0E;
  static const int _MSG_TYPE_BATTERY_LEVEL = 0x0F;
  static const int _MSG_TYPE_BULK_DICE_CONFIG = 0x27;

  // Global parameters
  static const int _GLOBAL_PARAM_DIE_TYPE = 0x01;
  static const int _GLOBAL_PARAM_DIE_COLOR = 0x02;
  static const int _GLOBAL_PARAM_DIE_ID = 0x03;
  static const int _GLOBAL_PARAM_ROLL_TIMEOUT = 0x04;

  // Notification identifiers
  static const int _NOTIFY_ROLL_STATE = 0x01;
  static const int _NOTIFY_FAKE_ROLL = 0x02;
  static const int _NOTIFY_TILT_STATE = 0x03;
  static const int _NOTIFY_MOVE_STATE = 0x04;

  // Die states
  static const int _ROLL_STATE_ON_TABLE = 0x00;
  static const int _ROLL_STATE_ROLLING = 0x01;
  static const int _ROLL_STATE_HANDLING = 0x02;

  // Instance variables
  Map<String, BluetoothDevice> _connectedDice = {};
  Map<String, StreamSubscription> _deviceSubscriptions = {};
  Map<String, DieType> _dieTypes = {};
  Map<String, DieColor> _dieColors = {};
  Map<String, int> _batteryLevels = {};
  Map<String, int> _currentValues = {};
  Map<String, bool> _isRolling = {};

  // Event listeners
  final Map<DieEvent, List<Function>> _eventListeners = {};

  // Singleton instance
  static final GoDice _instance = GoDice._internal();

  factory GoDice() => _instance;

  GoDice._internal();

  /// Start scanning for GoDice devices
  Future<void> startScan() async {
    try {
      // Check if Bluetooth is available and turned on
      if (await FlutterBluePlus.isSupported == false) {
        print("Bluetooth is not available on this device");
        return;
      }

      await FlutterBluePlus.adapterState
          .firstWhere(
            (state) => state == BluetoothAdapterState.on,
            orElse: () => throw TimeoutException('Bluetooth did not turn on'),
          )
          .timeout(
            Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Bluetooth connection timeout after 10 seconds'),
          );

      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10), withServices: [SERVICE_UUID]);

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (result.device.name.startsWith('GoDice_')) {
            print("Found GoDice: ${result.device.name}");
          }
        }
      });
    } catch (e) {
      print("Error scanning for devices: $e");
    }
  }

  /// Stop scanning for devices
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Connect to a GoDice device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // Connect to the device
      await device.connect();

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? goDiceService;

      // Find the GoDice service
      for (BluetoothService service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          goDiceService = service;
          break;
        }
      }

      if (goDiceService == null) {
        print("GoDice service not found on device ${device.name}");
        await device.disconnect();
        return false;
      }

      // Find the TX characteristic to subscribe to notifications
      BluetoothCharacteristic? txCharacteristic;
      for (BluetoothCharacteristic characteristic in goDiceService.characteristics) {
        if (characteristic.uuid.toString() == TX_CHARACTERISTIC_UUID) {
          txCharacteristic = characteristic;

          // Subscribe to notifications
          await characteristic.setNotifyValue(true);
          _deviceSubscriptions[device.remoteId.str] = characteristic.lastValueStream.listen((value) {
            _handleNotification(device.remoteId.str, value);
          });

          break;
        }
      }

      if (txCharacteristic == null) {
        print("TX characteristic not found on device ${device.name}");
        await device.disconnect();
        return false;
      }

      // Store the connected device
      _connectedDice[device.remoteId.str] = device;
      _isRolling[device.remoteId.str] = false;

      // Request die information
      await requestDieType(device);
      await requestBatteryLevel(device);
      await requestDieColor(device);

      // Trigger connection event
      _triggerEvent(DieEvent.connection, {'deviceId': device.remoteId.str, 'isConnected': true, 'deviceName': device.name});

      return true;
    } catch (e) {
      print("Error connecting to device: $e");
      return false;
    }
  }

  /// Disconnect from a GoDice device
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    try {
      // Cancel notification subscription
      _deviceSubscriptions[device.remoteId.str]?.cancel();
      _deviceSubscriptions.remove(device.remoteId.str);

      // Disconnect from the device
      await device.disconnect();

      // Remove from connected dice
      _connectedDice.remove(device.remoteId.str);
      _dieTypes.remove(device.remoteId.str);
      _dieColors.remove(device.remoteId.str);
      _batteryLevels.remove(device.remoteId.str);
      _currentValues.remove(device.remoteId.str);
      _isRolling.remove(device.remoteId.str);

      // Trigger connection event
      _triggerEvent(DieEvent.connection, {'deviceId': device.remoteId.str, 'isConnected': false, 'deviceName': device.name});
    } catch (e) {
      print("Error disconnecting from device: $e");
    }
  }

  /// Request the die type from a connected die
  Future<void> requestDieType(BluetoothDevice device) async {
    await _sendGlobalParamRequest(device, _GLOBAL_PARAM_DIE_TYPE);
  }

  /// Request the battery level from a connected die
  Future<void> requestBatteryLevel(BluetoothDevice device) async {
    await _writeCommand(device, [_MSG_TYPE_BATTERY_LEVEL]);
  }

  /// Request the die color from a connected die
  Future<void> requestDieColor(BluetoothDevice device) async {
    await _sendGlobalParamRequest(device, _GLOBAL_PARAM_DIE_COLOR);
  }

  /// Set the LED color on the die
  Future<void> setLedColor(
    BluetoothDevice device, {
    required int red,
    required int green,
    required int blue,
    required int onTime,
    required int offTime,
    required int duration,
  }) async {
    List<int> command = [
      _MSG_TYPE_LED_CONFIG,
      red,
      green,
      blue,
      onTime & 0xFF,
      (onTime >> 8) & 0xFF,
      offTime & 0xFF,
      (offTime >> 8) & 0xFF,
      duration & 0xFF,
      (duration >> 8) & 0xFF,
    ];

    await _writeCommand(device, command);
  }

  /**
   * Pulses LEDs for set time and color
   * @param {number} pulseCount - an integer of how many times the pulse will repeat (max 255)
   * @param {number} onTime - how much time should the LED be ON each pulse (units of 10ms, max 255) 
   * @param {number} offTime - how much time should the LED be OFF each pulse (units of 10ms, max 255)
   * @param {Array} RGB - an array to control both LEDs color's in the following format '[R, G, B]' 
   *                     where R, G and B are number in the range of 0-255
   */
  Future<void> pulseLed({int? pulseCount, int? onTime, int? offTime, List<int>? RGB}) async {
    // Get the device to control
    final deviceIds = _connectedDice.keys.toList();
    if (deviceIds.isEmpty) {
      print("No connected dice to pulse LEDs");
      return;
    }

    // Validate and cap parameters
    final int count = (pulseCount == null) ? 1 : (pulseCount < 0 ? 0 : (pulseCount > 255 ? 255 : pulseCount));
    final int on = (onTime == null) ? 50 : (onTime < 0 ? 0 : (onTime > 255 ? 255 : onTime));
    final int off = (offTime == null) ? 50 : (offTime < 0 ? 0 : (offTime > 255 ? 255 : offTime));

    // Default RGB to white if not provided
    final r = RGB != null ? RGB[0] : 255;
    final g = RGB != null ? RGB[1] : 255;
    final b = RGB != null ? RGB[2] : 255;

    for (final deviceId in deviceIds) {
      final device = _connectedDice[deviceId];

      // Calculate duration based on pulse count and timing
      // Total duration = pulseCount * (onTime + offTime) * 10ms
      final durationMs = count * (on + off) * 10;
      // Convert to 16-bit value (LSB, MSB)
      final durationLow = durationMs & 0xFF;
      final durationHigh = (durationMs >> 8) & 0xFF;

      // Setup the LED config command
      final List<int> command = [
        _MSG_TYPE_LED_CONFIG,
        r, g, b, // RGB for LED 1
        r, g, b, // Same RGB for LED 2
        on,
        0, // On time (LSB, MSB) - in units of 10ms
        off,
        0, // Off time (LSB, MSB) - in units of 10ms
        durationLow,
        durationHigh // Total duration (LSB, MSB) - in ms
      ];

      await _writeCommand(device!, command);
    }
  }

  /// Add an event listener
  void addEventListener(DieEvent event, Function callback) {
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = [];
    }
    _eventListeners[event]!.add(callback);
  }

  /// Remove an event listener
  void removeEventListener(DieEvent event, Function callback) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(callback);
    }
  }

  /// Get the current roll value for a die
  int? getRollValue(String deviceId) {
    return _currentValues[deviceId];
  }

  /// Get the die type for a connected die
  DieType? getDieType(String deviceId) {
    return _dieTypes[deviceId];
  }

  /// Get the die color for a connected die
  DieColor? getDieColor(String deviceId) {
    return _dieColors[deviceId];
  }

  /// Get the battery level for a connected die
  int? getBatteryLevel(String deviceId) {
    return _batteryLevels[deviceId];
  }

  /// Check if a die is currently rolling
  bool isRolling(String deviceId) {
    return _isRolling[deviceId] ?? false;
  }

  /// Get list of connected dice
  List<BluetoothDevice> getConnectedDice() {
    return _connectedDice.values.toList();
  }

  // Private methods

  /// Send a global parameter request
  Future<void> _sendGlobalParamRequest(BluetoothDevice device, int paramId) async {
    await _writeCommand(device, [_MSG_TYPE_GLOBAL_PARAM, paramId]);
  }

  /// Write a command to the die
  Future<void> _writeCommand(BluetoothDevice device, List<int> data) async {
    try {
      // Find the GoDice service
      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? goDiceService;

      for (BluetoothService service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          goDiceService = service;
          break;
        }
      }

      if (goDiceService == null) {
        print("GoDice service not found");
        return;
      }

      // Find the RX characteristic to write to
      BluetoothCharacteristic? rxCharacteristic;
      for (BluetoothCharacteristic characteristic in goDiceService.characteristics) {
        if (characteristic.uuid.toString() == RX_CHARACTERISTIC_UUID) {
          rxCharacteristic = characteristic;
          break;
        }
      }

      if (rxCharacteristic == null) {
        print("RX characteristic not found");
        return;
      }

      // Write the command
      await rxCharacteristic.write(data);
    } catch (e) {
      print("Error writing command: $e");
    }
  }

  /// Handle notifications from the die
  void _handleNotification(String deviceId, List<int> data) {
    if (data.isEmpty) return;

    int messageType = data[0];

    switch (messageType) {
      case _MSG_TYPE_GLOBAL_PARAM:
        _handleGlobalParam(deviceId, data);
        break;
      case _MSG_TYPE_STABLE_FACE:
        _handleStableFace(deviceId, data);
        break;
      case _MSG_TYPE_NOTIFICATION:
        _handleNotificationMessage(deviceId, data);
        break;
      case _MSG_TYPE_BATTERY_LEVEL:
        _handleBatteryLevel(deviceId, data);
        break;
    }
  }

  /// Handle global parameter responses
  void _handleGlobalParam(String deviceId, List<int> data) {
    if (data.length < 3) return;

    int paramId = data[1];

    switch (paramId) {
      case _GLOBAL_PARAM_DIE_TYPE:
        _handleDieType(deviceId, data[2]);
        break;
      case _GLOBAL_PARAM_DIE_COLOR:
        _handleDieColor(deviceId, data[2]);
        break;
    }
  }

  /// Handle die type information
  void _handleDieType(String deviceId, int typeValue) {
    DieType dieType;

    switch (typeValue) {
      case 0:
        dieType = DieType.d6;
        break;
      case 1:
        dieType = DieType.d20;
        break;
      case 2:
        dieType = DieType.d12;
        break;
      case 3:
        dieType = DieType.d10;
        break;
      case 4:
        dieType = DieType.d10X;
        break;
      case 5:
        dieType = DieType.d8;
        break;
      case 6:
        dieType = DieType.d4;
        break;
      case 7:
        dieType = DieType.d7;
        break;
      case 8:
        dieType = DieType.dF;
        break;
      default:
        dieType = DieType.custom;
    }

    _dieTypes[deviceId] = dieType;

    _triggerEvent(DieEvent.dieType, {'deviceId': deviceId, 'dieType': dieType});
  }

  /// Handle die color information
  void _handleDieColor(String deviceId, int colorValue) {
    DieColor dieColor;

    switch (colorValue) {
      case 0:
        dieColor = DieColor.black;
        break;
      case 1:
        dieColor = DieColor.red;
        break;
      case 2:
        dieColor = DieColor.green;
        break;
      case 3:
        dieColor = DieColor.blue;
        break;
      case 4:
        dieColor = DieColor.yellow;
        break;
      case 5:
        dieColor = DieColor.orange;
        break;
      case 6:
        dieColor = DieColor.purple;
        break;
      default:
        dieColor = DieColor.unknown;
    }

    _dieColors[deviceId] = dieColor;

    _triggerEvent(DieEvent.color, {'deviceId': deviceId, 'dieColor': dieColor});
  }

  /// Handle stable face (roll result) notifications
  void _handleStableFace(String deviceId, List<int> data) {
    if (data.length < 3) return;

    int face = data[1];
    // XYZ vector data would be in positions 2-7 if needed

    _currentValues[deviceId] = face;
    _isRolling[deviceId] = false;

    _triggerEvent(DieEvent.stableRoll, {'deviceId': deviceId, 'face': face, 'dieType': _dieTypes[deviceId]});
  }

  /// Handle notification messages
  void _handleNotificationMessage(String deviceId, List<int> data) {
    if (data.length < 3) return;

    int notificationType = data[1];
    int notificationValue = data[2];

    switch (notificationType) {
      case _NOTIFY_ROLL_STATE:
        _handleRollState(deviceId, notificationValue);
        break;
      case _NOTIFY_FAKE_ROLL:
        _handleFakeRoll(deviceId, notificationValue);
        break;
      case _NOTIFY_TILT_STATE:
      case _NOTIFY_MOVE_STATE:
        _handleTiltMove(deviceId, notificationType, notificationValue);
        break;
    }
  }

  /// Handle roll state changes
  void _handleRollState(String deviceId, int state) {
    if (state == _ROLL_STATE_ROLLING) {
      _isRolling[deviceId] = true;

      _triggerEvent(DieEvent.rollStart, {'deviceId': deviceId});
    }

    _triggerEvent(DieEvent.dieState, {'deviceId': deviceId, 'state': state});
  }

  /// Handle fake roll notifications
  void _handleFakeRoll(String deviceId, int face) {
    _triggerEvent(DieEvent.fakeRoll, {'deviceId': deviceId, 'face': face});
  }

  /// Handle tilt/move notifications
  void _handleTiltMove(String deviceId, int type, int value) {
    _triggerEvent(DieEvent.tiltMove, {'deviceId': deviceId, 'type': type, 'value': value});
  }

  /// Handle battery level notifications
  void _handleBatteryLevel(String deviceId, List<int> data) {
    if (data.length < 2) return;

    int batteryLevel = data[1];
    _batteryLevels[deviceId] = batteryLevel;

    _triggerEvent(DieEvent.batteryLevel, {'deviceId': deviceId, 'level': batteryLevel});
  }

  /// Trigger an event to all registered listeners
  void _triggerEvent(DieEvent event, Map<String, dynamic> data) {
    if (_eventListeners.containsKey(event)) {
      for (Function callback in _eventListeners[event]!) {
        callback(data);
      }
    }
  }
}

// Example usage class
class GoDiceExample {
  final GoDice goDice = GoDice();

  Future<void> init() async {
    // Add event listeners
    goDice.addEventListener(DieEvent.connection, _onDieConnection);
    goDice.addEventListener(DieEvent.batteryLevel, _onBatteryLevel);
    goDice.addEventListener(DieEvent.dieType, _onDieType);
    goDice.addEventListener(DieEvent.stableRoll, _onStableRoll);
    goDice.addEventListener(DieEvent.rollStart, _onRollStart);

    // Start scanning for dice
    await goDice.startScan();
  }

  void connectToDie(BluetoothDevice device) async {
    bool connected = await goDice.connectToDevice(device);
    print("Connected to die: $connected");
  }

  void setLedColor(BluetoothDevice device, {required int r, required int g, required int b}) async {
    await goDice.setLedColor(
      device,
      red: r,
      green: g,
      blue: b,
      onTime: 100,
      // LED on time in ms
      offTime: 100,
      // LED off time in ms
      duration: 2000, // Total duration in ms
    );
  }

  // Event handlers
  void _onDieConnection(Map<String, dynamic> data) {
    print("Die connection changed: ${data['deviceName']} - ${data['isConnected']}");
  }

  void _onBatteryLevel(Map<String, dynamic> data) {
    print("Battery level: ${data['level']}%");
  }

  void _onDieType(Map<String, dynamic> data) {
    print("Die type: ${data['dieType']}");
  }

  void _onStableRoll(Map<String, dynamic> data) {
    print("Roll result: ${data['face']}");
  }

  void _onRollStart(Map<String, dynamic> data) {
    print("Die started rolling");
  }
}