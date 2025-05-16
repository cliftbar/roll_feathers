import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:roll_feathers/pixel/ha.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:roll_feathers/roll_feathers_controller.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "local.env");

  // Initialize FlutterBluePlus
  FlutterBluePlus.setLogLevel(LogLevel.info, color: true);

  runApp(const MaterialApp(home: BleScannerWidget()));
}

class BleScannerWidget extends StatefulWidget {
  const BleScannerWidget({super.key});

  @override
  State<BleScannerWidget> createState() => _BleScannerWidgetState();
}

class _BleScannerWidgetState extends State<BleScannerWidget> {
  final Map<String, Color> _rollingColors = {};
  final RollFeathersController _rfController = RollFeathersController();
  final List<String> _rollHistory = []; // Add this line to store roll history

  @override
  void initState() {
    super.initState();
    try {
      _rfController.init();
      _rollingColors.clear();
    } on BluetoothNotSupported catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Initialization error: $e')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scanning error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roll Feathers')),
      body: Row(
        children: [
          // First column - existing StreamBuilder (taking half the width)
          Expanded(
            child: StreamBuilder<List<PixelDie>>(
              stream: _rfController.getDeviceStream(),
              initialData: const [],
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return const Center(child: Text('No devices found'));
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final die = devices[index];
                    _rollingColors[die.device.remoteId.toString()] ??=
                        Colors.black;
                    die.messageRxCallbacks[MessageType.rollState] = (msg) {
                      MessageRollState rollStateMsg = msg as MessageRollState;
                      if (rollStateMsg.rollState == RollState.rolled.index ||
                          rollStateMsg.rollState == RollState.onFace.index) {
                        _rollingColors[die.device.remoteId.toString()] =
                            Colors.green;

                        bool allDiceRolled = devices.every(
                          (d) =>
                              d.state.rollState == RollState.rolled.index ||
                              d.state.rollState == RollState.onFace.index,
                        );

                        _rfController.updateDieValue(die);
                        if (allDiceRolled && _rfController.isRolling()) {
                          _rfController.stopRolling();
                          // Add the roll result to history
                          setState(() {
                            _rollHistory.insert(
                                0,
                                'Roll: Sum ${_rfController.rollTotal()} (Adv: ${_rfController.rollMax()}, DisAdv: ${_rfController.rollMin()})');
                          });
                        }

                        setState(() {});
                      } else if (rollStateMsg.rollState ==
                          RollState.rolling.index) {
                        _rollingColors[die.device.remoteId.toString()] =
                            Colors.orange;

                        if (!_rfController.isRolling()) {
                          _rfController.startRolling((timer) {
                            setState(() {});
                          });
                        }
                        setState(() {});
                      }
                    };
                    die.messageRxCallbacks[MessageType.iAmADie] = (msg) {
                      setState(() {});
                    };
                    return ListTile(
                      textColor:
                          _rollingColors[die.device.remoteId.toString()],
                      title: Text(
                        die.device.platformName.isEmpty
                            ? 'Unknown Device ${die.device.remoteId}'
                            : '${die.device.platformName} ${die.state.batteryLevel} Sum ${_rfController.rollTotal()} DisAdv ${_rfController.rollMin()} Adv ${_rfController.rollMax()}',
                      ),
                      subtitle: Text(
                        '${RollState.values[die.state.rollState ?? RollState.unknown.index].name} ${die.state.currentFaceValue}',
                      ),
                      onTap: () {
                        var blinker = BlinkMessage();
                        die.sendMessage(blinker);
                        HomeAssistantController().blinkEntity(blinker);
                      },
                    );
                  },
                );
              },
            ),
          ),
          // Second column - roll history (taking half the width)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Roll History',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear_all),
                          onPressed: () {
                            setState(() {
                              _rollHistory.clear();
                            });
                          },
                          tooltip: 'Clear roll history',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _rollHistory.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_rollHistory[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _rfController.startScanning,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  @override
  void dispose() {
    _rfController.dispose();
    super.dispose();
  }
}