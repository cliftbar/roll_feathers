import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:roll_feathers/controllers/roll_feathers_controller.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/pixel/pixel_messages.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/repositories/home_assistant_repository.dart';
import 'package:roll_feathers/ui/main_screen_vm.dart';

class MainScreenWidget extends StatefulWidget {
  const MainScreenWidget._(this.viewModel);

  static Future<MainScreenWidget> create(AppRepository appRepo, HaRepository haRepo) async {
    var vm = MainScreenViewModel(appRepo, haRepo);

    var widget = MainScreenWidget._(vm);

    return widget;
  }

  final MainScreenViewModel viewModel;

  @override
  State<MainScreenWidget> createState() => _MainScreenWidgetState();
}

class _MainScreenWidgetState extends State<MainScreenWidget> {
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

  // First, add a drawer to the Scaffold
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('Settings', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            // Why does this get notified, when the view model is the main screen view model?
            ListenableBuilder(
              listenable: widget.viewModel,
              builder: (context, _) {
                return ListTile(
                  leading: Icon(widget.viewModel.themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
                  title: Text(widget.viewModel.themeMode == ThemeMode.light ? 'Dark Mode' : 'Light Mode'),
                  onTap: () {
                    widget.viewModel.toggleTheme.execute();
                    Navigator.pop(context);
                  },
                );
              },
            ),
            ListenableBuilder(
              listenable: widget.viewModel,
              builder: (context, _) {
                return ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('Home Assistant Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    _showHomeAssistantSettings(context, widget.viewModel);
                  },
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('Roll Feathers'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FloatingActionButton(
              onPressed: _rfController.startScanning,
              child: const Icon(Icons.refresh),
              mini: true,
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
                    print(Theme.of(context).textTheme.labelMedium?.color);
                    // _rollingColors[die.device.remoteId.toString()] ??= Theme.of(context).textTheme.labelMedium?.color ?? Colors.pink;
                    die.messageRxCallbacks[MessageType.rollState] = (msg) {
                      MessageRollState rollStateMsg = msg as MessageRollState;
                      if (rollStateMsg.rollState == RollState.rolled.index ||
                          rollStateMsg.rollState == RollState.onFace.index) {
                        // _rollingColors[die.device.remoteId.toString()] = Colors.green;

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
                        // _rollingColors[die.device.remoteId.toString()] = Colors.orange;

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
                      textColor: _getRollingTextColor(die, context),
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
                            final entityController = TextEditingController(
                              text: die.haEntityTargets.firstOrNull ?? "",
                            ); // Add controller for entity field

                            return AlertDialog(
                              title: const Text('Die Settings'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Pick a color'),
                                    ColorPicker(
                                      pickerColor: currentColor,
                                      onColorChanged: (Color color) {
                                        currentColor = color;
                                      },
                                      pickerAreaHeightPercent: 0.8,
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: entityController,
                                      decoration: const InputDecoration(
                                        labelText: 'Home Assistant Entity',
                                        hintText: 'light.bedroom',
                                        helperText: 'Leave empty to use default entity',
                                      ),
                                    ),
                                  ],
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
                                    widget.viewModel.blink.execute(currentColor, die);
                                    _rfController.blink(currentColor, die);
                                    print('blink $currentColor');
                                  },
                                ),
                                TextButton(
                                  child: const Text('Save'),
                                  onPressed: () {
                                    setState(() {
                                      _blinkColors[die.device.remoteId.str] = currentColor;
                                      _rfController.addDieEntity(die, entityController.text);
                                      // die.haEntityTargets.add(entityController.text);
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

  void _showHomeAssistantSettings(BuildContext context, MainScreenViewModel vm) async {
    // var haSettings = await _rfController.getHaSettings();
    var haConfig = vm.getHaConfig;
    final urlController = TextEditingController(text: haConfig.url);
    final tokenController = TextEditingController(text: haConfig.token);
    final entityController = TextEditingController(text: haConfig.entity);
    bool isEnabled = haConfig.enabled;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          // Use StatefulBuilder to manage toggle state
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Home Assistant Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Enable Home Assistant'),
                      value: isEnabled,
                      onChanged: (bool value) {
                        setState(() {
                          isEnabled = value;
                        });
                      },
                    ),
                    const Divider(),
                    TextField(
                      controller: urlController,
                      enabled: isEnabled,
                      decoration: const InputDecoration(
                        labelText: 'Home Assistant URL',
                        hintText: 'http://homeassistant.local:8123',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: tokenController,
                      enabled: isEnabled,
                      decoration: const InputDecoration(labelText: 'Long-Lived Access Token'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: entityController,
                      enabled: isEnabled,
                      decoration: const InputDecoration(labelText: 'Light Entity ID', hintText: 'light.living_room'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () {
                    vm.setHaConfig.execute(isEnabled, urlController.text, tokenController.text, entityController.text);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getRollingTextColor(PixelDie die, BuildContext context) {
    switch (RollState.values[die.state.rollState ?? 0]) {
      case RollState.rolling:
      case RollState.handling:
        return Colors.orange;
      case RollState.onFace:
      case RollState.rolled:
      default:
        return Theme.of(context).textTheme.bodyMedium?.color! ?? Colors.pink;
    }
  }

  @override
  void dispose() {
    _rfController.dispose();
    super.dispose();
  }
}
