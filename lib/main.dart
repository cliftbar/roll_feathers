import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
  final List<String> _rollHistory = [];
  final Map<String, Color> _blinkColors = {}; // Add this new variable
  bool _withAdvantage = false; // Add this line
  bool _withDisadvantage = false; // Add this line

  @override
  void initState() {
    super.initState();
    try {
      _rfController.init();
      _rollingColors.clear();
    } on BluetoothNotSupported catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Initialization error: $e')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanning error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roll Feathers'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FloatingActionButton(
              onPressed: _rfController.startScanning,
              child: const Icon(Icons.refresh),
              mini: true, // Makes the FAB smaller to fit in the AppBar
            ),
          ),
        ],
      ),
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
                    _rollingColors[die.device.remoteId.toString()] ??= Colors.black;
                    die.messageRxCallbacks[MessageType.rollState] = (msg) {
                      MessageRollState rollStateMsg = msg as MessageRollState;
                      if (rollStateMsg.rollState == RollState.rolled.index ||
                          rollStateMsg.rollState == RollState.onFace.index) {
                        _rollingColors[die.device.remoteId.toString()] = Colors.green;

                        bool allDiceRolled = devices.every(
                          (d) =>
                              d.state.rollState == RollState.rolled.index ||
                              d.state.rollState == RollState.onFace.index,
                        );

                        _rfController.updateDieValue(die);
                        if (allDiceRolled && _rfController.isRolling()) {
                          _rfController.stopRolling();
                          var rollType = RollType.sum;
                          if (_withAdvantage) {
                            rollType = RollType.advantage;
                          } else if (_withDisadvantage) {
                            rollType = RollType.disadvantage;
                          }
                          var result = _rfController.stopRollWithResult(rollType: rollType, totalColors: _blinkColors);
                          // Add the roll result to history with advantage/disadvantage information
                          setState(() {
                            String rollResult = 'Roll';
                            if (_withAdvantage) {
                              rollResult += ' (Adv): $result';
                            } else if (_withDisadvantage) {
                              rollResult += ' (Dis): $result';
                            } else {
                              rollResult += ': $result';
                            }
                            _rollHistory.insert(0, rollResult);
                          });
                        }

                        setState(() {});
                      } else if (rollStateMsg.rollState == RollState.rolling.index) {
                        _rollingColors[die.device.remoteId.toString()] = Colors.orange;

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
                      textColor: _rollingColors[die.device.remoteId.toString()],
                      title: Text(
                        die.device.platformName.isEmpty
                            ? 'Unknown Device ${die.device.remoteId}'
                            : die.device.platformName,
                      ),
                      subtitle: Text(
                        '${RollState.values[die.state.rollState ?? RollState.unknown.index].name} ${die.state.currentFaceValue}',
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            Color currentColor = _blinkColors[die.device.remoteId.str] ?? Colors.white;
                            return AlertDialog(
                              title: const Text('Pick a color'),
                              content: SingleChildScrollView(
                                child: ColorPicker(
                                  pickerColor: currentColor,
                                  onColorChanged: (Color color) {
                                    currentColor = color;
                                  },
                                  pickerAreaHeightPercent: 0.8,
                                ),
                              ),
                              actions: <Widget>[
                                TextButton(
                                  child: const Text('Cancel'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                                TextButton(
                                  child: const Text('Blink'),
                                  onPressed: () {
                                    print('blink $currentColor');
                                    var blinker = BlinkMessage(blinkColor: currentColor);
                                    die.sendMessage(blinker);
                                    HomeAssistantController().blinkEntity(blinker);
                                  },
                                ),
                                TextButton(
                                  child: const Text('Save'),
                                  onPressed: () {
                                    setState(() {
                                      _blinkColors[die.device.remoteId.str] = currentColor;
                                    });
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ],
                            );
                          },
                        );
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
              decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 1))),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Roll History', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Wrap(
                      spacing: 8.0, // gap between adjacent items
                      runSpacing: 4.0, // gap between lines
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Wrap(
                          spacing: 8.0,
                          children: [
                            SizedBox(
                              width: 140, // Fixed width for consistency
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _withAdvantage,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        _withAdvantage = value ?? false;
                                        if (_withAdvantage) {
                                          _withDisadvantage = false;
                                        }
                                      });
                                    },
                                  ),
                                  const Text('Advantage'),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 140, // Fixed width for consistency
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _withDisadvantage,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        _withDisadvantage = value ?? false;
                                        if (_withDisadvantage) {
                                          _withAdvantage = false;
                                        }
                                      });
                                    },
                                  ),
                                  const Text('Disadvantage'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                          onPressed: () {
                            setState(() {
                              _rollHistory.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _rollHistory.length,
                      itemBuilder: (context, index) {
                        return ListTile(title: Text(_rollHistory[index]));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Remove the floatingActionButton property from here
    );
  }

  @override
  void dispose() {
    _rfController.dispose();
    super.dispose();
  }
}
