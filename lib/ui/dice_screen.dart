import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/ui/dice_screen_vm.dart';
import 'package:tuple/tuple.dart';

import 'app_settings/app_settings_screen.dart';

class DiceScreenWidget extends StatefulWidget {
  const DiceScreenWidget._(this.viewModel, this.appSettingsWidget);

  static Future<DiceScreenWidget> create(DiWrapper di, AppSettingsWidget appSettings) async {
    var vm = DiceScreenViewModel(di);
    var widget = DiceScreenWidget._(vm, appSettings);

    return widget;
  }

  final DiceScreenViewModel viewModel;
  final AppSettingsWidget appSettingsWidget;

  @override
  State<DiceScreenWidget> createState() => _DiceScreenWidgetState();
}

class _DiceScreenWidgetState extends State<DiceScreenWidget> {
  bool _rollMax = false;
  bool _rollMin = false;
  bool _rollVirtualDice = true;

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
            Container(
              decoration: BoxDecoration(color: Colors.blue),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: SafeArea(
                bottom: false,
                child: Text('Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              ),
            ),
            widget.appSettingsWidget,
            // Why does this get notified, when the view model is the main screen view model?
            Card(
              margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Dice', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _rollVirtualDice,
                      onChanged: (bool value) {
                        setState(() {
                          _setWithVirtualDice(value);
                        });
                      },
                      title: const Text("Auto-roll"),
                    ),
                    ListTile(
                      onTap: () {
                        _showAddVirtualDieDialog(context);
                      },
                      title: const Text('Add New Virtual Die'),
                      leading: const Icon(Icons.add),
                    ),
                    ListTile(
                      onTap: () {
                        widget.viewModel.disconnectAllDice.execute();
                      },
                      title: const Text("Remove All Dice"),
                      leading: const Icon(Icons.highlight_remove_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(title: const Text('Roll Feathers'), actions: []),
      body: Row(
        children: [
          // First column - existing StreamBuilder (taking half the width)
          Expanded(
            child: Column(
              children: [
                Wrap(
                  // TODO: second row so alignment works?
                  children: [
                    _makeAutoRollSwitch(),
                    TextButton.icon(
                      onPressed: () {
                        _showAddVirtualDieDialog(context);
                      },
                      label: const Text("Add Die"),
                      icon: const Icon(Icons.add),
                    ), // _makeBleScanButton(),
                    ListenableBuilder(
                      listenable: widget.appSettingsWidget.vm,
                      builder: (context, _) {
                        return TextButton.icon(
                          onPressed:
                              widget.appSettingsWidget.vm.bleIsEnabled()
                                  ? () {
                                    widget.appSettingsWidget.vm.startBleScan.execute();
                                  }
                                  : null,
                          label:
                              widget.appSettingsWidget.vm.bleIsEnabled()
                                  ? Text(kIsWeb ? "Pair Die" : "Scan")
                                  : Text("BLE Disabled"),
                          icon:
                              widget.appSettingsWidget.vm.bleIsEnabled()
                                  ? const Icon(Icons.bluetooth_searching)
                                  : const Icon(Icons.bluetooth_disabled),
                        );
                      },
                    ),
                    TextButton.icon(
                      onPressed: () {
                        widget.viewModel.rollAllVirtualDice.execute(true);
                      },
                      label: const Text("Roll"),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ), // TODO: Does this need to be listenable?  does the stream already handle updates?
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.viewModel,
                    builder: (context, _) {
                      return StreamBuilder<Map<String, GenericDie>>(
                        stream: widget.viewModel.getDeviceStream(),
                        initialData: const {},
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(child: Text('Error: ${snapshot.error}'));
                          }

                          final List<GenericDie> devices = snapshot.data?.values.toList() ?? [];

                          if (devices.isEmpty) {
                            return const Center(child: Text('No dice added'));
                          }
                          return ListView.builder(
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final die = devices[index];

                              return _makeDiceText(die, context);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
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
                        // Wrap(
                        //   spacing: 8.0,
                        //   children: [
                        //     Row(
                        //       mainAxisSize: MainAxisSize.min,
                        //       children: [
                        //         const Text('Roll Type: '),
                        //         Checkbox(
                        //           value: _rollMax,
                        //           onChanged: (bool? value) {
                        //             setState(() {
                        //               _rollMax = value ?? false;
                        //               if (_rollMax) {
                        //                 _rollMin = false;
                        //               }
                        //               _setRollType();
                        //             });
                        //           },
                        //         ),
                        //         const Text('Maximum'),
                        //       ],
                        //     ),
                        //     SizedBox(
                        //       width: 140, // Fixed width for consistency
                        //       child: Row(
                        //         mainAxisSize: MainAxisSize.min,
                        //         children: [
                        //           Checkbox(
                        //             value: _rollMin,
                        //             onChanged: (bool? value) {
                        //               setState(() {
                        //                 _rollMin = value ?? false;
                        //                 if (_rollMin) {
                        //                   _rollMax = false;
                        //                 }
                        //                 _setRollType();
                        //               });
                        //             },
                        //           ),
                        //           const Text('Minimum'),
                        //         ],
                        //       ),
                        //     ),
                        //   ],
                        // ),
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
                            List<RollResult> rollResults = snapshot.data ?? [];
                            if (rollResults.isEmpty) {
                              return const Center(child: Text('Make some rolls!'));
                            }
                            return ListView.builder(
                              itemCount: rollResults.length,
                              itemBuilder: (context, index) {
                                return ListTile(title: _makeRollText(context, rollResults[index]));
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
    );
  }

  ListTile _makeDiceText(GenericDie die, BuildContext context) {
    return ListTile(
      textColor: _getBlinkColor(context, die),
      title: Text(die.friendlyName.isEmpty ? 'Unknown Device ${die.dieId}' : die.friendlyName),
      leading: Icon(Icons.hexagon),
      iconColor: _getRollingTextColor(die, context),
      subtitle: Text(_getDieText(die)),
      onTap: () {
        _singleDieSettings(context, die);
      },
    );
  }

  void _singleDieSettings(BuildContext context, GenericDie die) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        Color currentColor = die.blinkColor ?? Colors.white;
        final entityController = TextEditingController(
          text: die.haEntityTargets.firstOrNull ?? "",
        ); // Add controller for entity field
        var faceTuple = _makeFaceSelectorWidget(die);
        return ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) {
            return AlertDialog(
              title: Text('${die.friendlyName} Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Face Count"),
                    faceTuple.item1,
                    const Divider(),
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
                      enabled: widget.appSettingsWidget.vm.getHaConfig().enabled,
                      autocorrect: false,
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
                  child: const Text('Disconnect'),
                  onPressed: () {
                    widget.viewModel.disconnectDie.execute(die.dieId);
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () {
                    widget.viewModel.updateDieSettings.execute(
                      die,
                      currentColor,
                      entityController.text,
                      faceTuple.item2(),
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
  }

  String _getDieText(GenericDie die) {
    String valueString;
    DiceRollState rollState = DiceRollState.values[die.state.rollState ?? DiceRollState.unknown.index];
    switch (rollState) {
      case DiceRollState.rolling:
      case DiceRollState.handling:
        valueString = " rolling";
      case DiceRollState.rolled:
      case DiceRollState.onFace:
        valueString = " Value: ${die.state.currentFaceValue}";
      default:
        valueString = "";
    }

    return '${die.dType.name} ${die.state.batteryLevel}%$valueString ${die.dieId}';
  }

  // Helpers
  void _setRollType() {
    if (_rollMax) {
      widget.viewModel.setRollType.execute(RollType.max);
    } else if (_rollMin) {
      widget.viewModel.setRollType.execute(RollType.min);
    } else {
      widget.viewModel.setRollType.execute(RollType.sum);
    }
  }

  void _setWithVirtualDice(bool value) {
    _rollVirtualDice = value;
    widget.viewModel.setWithVirtualDice.execute(_rollVirtualDice);
  }

  RichText _makeRollText(BuildContext context, RollResult roll) {
    List<TextSpan> rollsWithColors =
        roll.rolls.entries
            .sortedBy((e) => e.value)
            .map(
              (entry) => TextSpan(
                text: "${entry.value}",
                style: DefaultTextStyle.of(
                  context,
                ).style.copyWith(color: _getBlinkColor(context, widget.viewModel.getDieById(entry.key))),
              ),
            )
            .toList();

    TextSpan rollType;
    if (roll.ruleName == null) {
      rollType = TextSpan(text: ": ${roll.rollResult}");
    } else {
      rollType = TextSpan(text: " <${roll.ruleName}>: ${roll.rollResult}");
    }
    // switch (roll.rollType) {
    //   case RollType.max:
    //     rollType = TextSpan(text: "<max>:  ${roll.rollResult}");
    //     // rollResult += ' <max>: ${roll.rollResult} ($rollString)';
    //     break;
    //   case RollType.min:
    //     rollType = TextSpan(text: "<min>:  ${roll.rollResult}");
    //     // rollResult += ' <min>: ${roll.rollResult} ($rollString)';
    //     break;
    //   default:
    //     rollType = TextSpan(text: "<sum>:  ${roll.rollResult}");
    //   // rollResult += '<sum>: ${roll.rollResult} ($rollString)';
    // }
    List<TextSpan> dynamicText = <TextSpan>[rollType, TextSpan(text: " (")];
    dynamicText.add(rollsWithColors[0]);
    for (var r in rollsWithColors.sublist(1)) {
      dynamicText.add(TextSpan(text: ", "));
      dynamicText.add(r);
    }
    dynamicText.add(TextSpan(text: ")"));

    var rt = RichText(text: TextSpan(text: "Roll", style: DefaultTextStyle.of(context).style, children: dynamicText));

    return rt;
  }

  Color _getRollingTextColor(GenericDie die, BuildContext context) {
    switch (DiceRollState.values[die.state.rollState ?? 0]) {
      case DiceRollState.rolling:
      case DiceRollState.handling:
        return Colors.orange;
      case DiceRollState.onFace:
      case DiceRollState.rolled:
      default:
        return _getBlinkColor(context, die);
    }
  }

  Color _getBlinkColor(BuildContext context, GenericDie? die) {
    return die?.blinkColor?.withAlpha(255) ??
        Theme.of(context).textTheme.bodyMedium?.color! ??
        (widget.appSettingsWidget.vm.themeMode == ThemeMode.dark ? Colors.white : Colors.black);
  }

  Card _makeAutoRollSwitch() {
    return Card(
      surfaceTintColor: Colors.transparent,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsetsGeometry.all(8),
        child: Row(
          children: [
            Switch(
              value: _rollVirtualDice,
              onChanged: (bool value) {
                setState(() {
                  _setWithVirtualDice(value);
                });
              },
            ),
            const Text("Auto-roll"),
          ],
        ),
      ),
    );
  }

  void _showAddVirtualDieDialog(BuildContext context) {
    final nameController = TextEditingController(text: "VirtualDie");
    final faceCountController = TextEditingController(text: "6");

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Virtual Die'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Die Name', hintText: 'Enter a name for the die'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: faceCountController,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Number of Faces',
                    hintText: 'Enter the number of faces',
                  ),
                  keyboardType: TextInputType.number,
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
              child: const Text('Add'),
              onPressed: () {
                final name = nameController.text;
                final faceCount = int.tryParse(faceCountController.text) ?? 6;
                widget.viewModel.addVirtualDie.execute(faceCount, name);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // this is a bad pattern x.x
  Tuple2<Widget, ValueGetter<GenericDType>> _makeFaceSelectorWidget(GenericDie die) {
    switch (die.type) {
      case GenericDieType.pixel:
        faceCallback() => die.dType;
        return Tuple2(Text(die.dType.name), faceCallback);
      case GenericDieType.godice:
        final List<DropdownMenuEntry<String>> menuEntries = UnmodifiableListView<DropdownMenuEntry<String>>(
          GodiceDieType.values
              .where((t) => t != GodiceDieType.d24)
              .map<DropdownMenuEntry<String>>(
                (GodiceDieType v) => DropdownMenuEntry<String>(value: v.name, label: v.name),
              ),
        );

        GenericDType dropdownValue = die.dType;
        var menu = DropdownMenu<String>(
          initialSelection: GodiceDieType.fromName(die.dType.name).name,
          onSelected: (String? value) {
            if (value != null) {
              dropdownValue = GodiceDieType.fromName(value).toDType();
            }
          },
          dropdownMenuEntries: menuEntries,
        );
        faceCallback() => dropdownValue;
        return Tuple2(menu, faceCallback);
      case GenericDieType.virtual:
        var faceCountUpdateController = TextEditingController(text: "${die.dType.faces}");
        faceCallback() {
          int value = int.parse(faceCountUpdateController.text);
          var dType = GenericDTypeFactory.fromIntId(value) ?? GenericDType("d${value.toString()}", value, value, 0, 1);
          return dType;
        }
        var col = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            TextFormField(
              controller: faceCountUpdateController,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Number of Faces', hintText: 'Enter the number of faces'),
              keyboardType: TextInputType.number,
            ),
          ],
        );

        return Tuple2(col, faceCallback);
    }
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }
}
