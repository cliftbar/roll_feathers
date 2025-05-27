import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/pixel/pixel.dart';
import 'package:roll_feathers/pixel/pixel_constants.dart';
import 'package:roll_feathers/ui/main_screen_vm.dart';

class MainScreenWidget extends StatefulWidget {
  const MainScreenWidget._(this.viewModel);

  static Future<MainScreenWidget> create(DiWrapper di) async {
    var vm = MainScreenViewModel(di);
    var widget = MainScreenWidget._(vm);

    return widget;
  }

  final MainScreenViewModel viewModel;

  @override
  State<MainScreenWidget> createState() => _MainScreenWidgetState();
}

class _MainScreenWidgetState extends State<MainScreenWidget> {
  bool _withAdvantage = false; // Add this line
  bool _withDisadvantage = false; // Add this line

  @override
  void initState() {
    super.initState();
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
              onPressed: () {
                widget.viewModel.startBleScan.execute();
              },
              mini: true,
              child: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // First column - existing StreamBuilder (taking half the width)
          Expanded(
            // TODO: Does this need to be listenable?  does the stream already handle updates?
            child: ListenableBuilder(
              listenable: widget.viewModel,
              builder: (context, _) {
                return StreamBuilder<Map<String, PixelDie>>(
                  stream: widget.viewModel.getDeviceStream(),
                  initialData: const {},
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final List<PixelDie> devices = snapshot.data?.values.toList() ?? [];

                    if (devices.isEmpty) {
                      return const Center(child: Text('No devices found'));
                    }
                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final die = devices[index];

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
                                Color currentColor =
                                    widget.viewModel.blinkColors[die.device.remoteId.str] ?? Colors.white;
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
                                          hexInputBar: true,
                                          paletteType: PaletteType.hueWheel,
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
                                        widget.viewModel.blink.execute(currentColor, die, entityController.text);
                                      },
                                    ),
                                    TextButton(
                                      child: const Text('Save'),
                                      onPressed: () {
                                        widget.viewModel.updateDieSettings.execute(
                                          die,
                                          currentColor,
                                          entityController.text,
                                        );
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
                );
              },
            ),
          ), // Second column - roll history (taking half the width)
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
                              width: 140,
                              // Fixed width for consistency
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
                                        _setRollType();
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
                                        _setRollType();
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
                            widget.viewModel.clearRollResultHistory.execute();
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: widget.viewModel,
                      builder: (context, _) {
                        return StreamBuilder(
                          stream: widget.viewModel.getResultsStream(),
                          builder: (context, snapshot) {
                            var rollResults = snapshot.data ?? [];
                            if (rollResults.isEmpty) {
                              return const Center(child: Text('Make some rolls!'));
                            }
                            return ListView.builder(
                              itemCount: rollResults.length,
                              itemBuilder: (context, index) {
                                return ListTile(title: Text(_makeRollText(rollResults[index])));
                              },
                            );
                          },
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
      // Remove the floatingActionButton property from here
    );
  }

  // Helpers
  void _setRollType() {
    if (_withAdvantage) {
      widget.viewModel.setRollType.execute(RollType.advantage);
    } else if (_withDisadvantage) {
      widget.viewModel.setRollType.execute(RollType.disadvantage);
    } else {
      widget.viewModel.setRollType.execute(RollType.sum);
    }
  }

  String _makeRollText(RollResult roll) {
    String rollResult = 'Roll';
    switch (roll.rollType) {
      case RollType.advantage:
        rollResult += ' (Adv): ${roll.rollResult}';
        break;
      case RollType.disadvantage:
        rollResult += ' (Dis): ${roll.rollResult}';
        break;
      default:
        rollResult += '(Sum): ${roll.rollResult}';
    }

    return rollResult;
  }

  void _showHomeAssistantSettings(BuildContext context, MainScreenViewModel vm) async {
    var haConfig = vm.getHaConfig();
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
                      decoration: const InputDecoration(labelText: 'Light Entity ID', hintText: 'light.game_room'),
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
        return widget.viewModel.blinkColors[die.deviceId]?.withAlpha(255) ??
            Theme.of(context).textTheme.bodyMedium?.color! ??
            (widget.viewModel.themeMode == ThemeMode.dark ? Colors.white : Colors.black);
    }
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }
}
