import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:roll_feathers/pixel/ha.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixelConstants.dart';
import 'package:roll_feathers/pixel/pixelMessages.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "local.env");

  // Initialize FlutterBluePlus
  FlutterBluePlus.setLogLevel(LogLevel.info, color: true);
  
  runApp(const MaterialApp(
    home: BleScannerWidget(),
  ));
}

class BleScannerWidget extends StatefulWidget {
  const BleScannerWidget({super.key});

  @override
  State<BleScannerWidget> createState() => _BleScannerWidgetState();
}

class _BleScannerWidgetState extends State<BleScannerWidget> {
  final BleScanManager _scanManager = BleScanManager();
  bool _initialized = false;
  final Map<String, Color> _rollingColors = {};
  final Map<String, int> _rollingDie = {};
  Timer? _rollUpdateTimer;
  bool _isRolling = false;

  @override
  void initState() {
    super.initState();
    _initializeBle();
    _rollingColors.clear();
  }

  Future<void> _initializeBle() async {
    if (_initialized) return;
    
    try {
      var supported = await _scanManager.checkSupported();
      if (!supported) {
        throw Exception("BLE Not Supported!");
      }

      await _scanManager.connect();


      _initialized = true;
      await _startScanning();
    } catch (e) {
      _initialized = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Initialization error: $e')),
        );
      }
    }
  }

  Future<void> _startScanning() async {
    print("_startScanning()");
    try {
      await _scanManager.scanForDevices();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanning error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
      ),
      body: StreamBuilder<List<PixelDie>>(
        stream: _scanManager.deviceStream,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          final devices = snapshot.data ?? [];

          if (devices.isEmpty) {
            return const Center(
              child: Text('No devices found'),
            );
          }

          return ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final die = devices[index];
              _rollingColors[die.device.remoteId.toString()] ??= Colors.black;
              die.messageRxCallbacks[MessageType.rollState] = (msg) {
                MessageRollState rollStateMsg = msg as MessageRollState;
                if (rollStateMsg.rollState == RollState.rolled.index ||
                    rollStateMsg.rollState == RollState.onFace.index) {
                  _rollingColors[die.device.remoteId.toString()] = Colors.green;

                  // Check if all dice have finished rolling
                  bool allDiceRolled = devices.every((d) =>
                  d.state.rollState == RollState.rolled.index ||
                      d.state.rollState == RollState.onFace.index);

                  _rollingDie[die.device.remoteId.str] = die.state.currentFaceValue!;
                  if (allDiceRolled && _isRolling) {
                    _rollUpdateTimer?.cancel();
                    _isRolling = false;
                  }

                  setState(() {
                    // UI will automatically update via StreamBuilder
                  });
                } else if (rollStateMsg.rollState == RollState.rolling.index) {
                  _rollingColors[die.device.remoteId.toString()] =
                      Colors.orange;
                  if (!_isRolling) {
                    _isRolling = true;
                    _rollingDie.clear();
                    _rollUpdateTimer?.cancel();
                    _rollUpdateTimer = Timer.periodic(
                        const Duration(milliseconds: 100), (timer) {
                      setState(() {});
                    });
                  }
                  setState(() {
                    // UI will automatically update via StreamBuilder
                  });
                }
              };
              die.messageRxCallbacks[MessageType.iAmADie] = (msg) {
                setState(() {
                  // UI will automatically update via StreamBuilder
                });
              };
              return ListTile(
                textColor: _rollingColors[die.device.remoteId.toString()],
                title: Text(die.device.platformName.isEmpty
                  ? 'Unknown Device ${die.device.remoteId}'
                  : '${die.device.platformName} ${die.state.batteryLevel} Sum ${_rollingDie.values.fold(0, (p, c) => p + c)} DisAdv ${_rollingDie.values.fold(21, min)} Adv ${_rollingDie.values.fold(0, max)}'),
                subtitle: Text('${RollState.values[die.state.rollState ?? RollState.unknown.index].name} ${die.state.currentFaceValue}'),
                onTap: () {
                  var blinker = BlinkMessage();
                  die.sendMessage(blinker);
                  HomeAssistantController().blinkEntity(blinker);
                  // Handle device selection
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startScanning,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  @override
  void dispose() {
    _scanManager.dispose();
    _rollUpdateTimer?.cancel();
    super.dispose();
  }
}