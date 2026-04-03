import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen_vm.dart';
import 'package:roll_feathers/ui/die_screen/die_list_tile.dart';
import 'package:roll_feathers/ui/die_screen/single_die_settings_dialog.dart';

import '../app_settings/app_settings_screen.dart';
import '../app_settings/app_settings_screen_vm.dart';

class DiceScreenWidget extends StatefulWidget {
  const DiceScreenWidget._(this.viewModel, this.settingsVm);

  static Future<DiceScreenWidget> create(DiWrapper di, AppSettingsScreenViewModel settingsVm) async {
    var vm = DiceScreenViewModel(di);
    return DiceScreenWidget._(vm, settingsVm);
  }

  final DiceScreenViewModel viewModel;
  final AppSettingsScreenViewModel settingsVm;

  @override
  State<DiceScreenWidget> createState() => _DiceScreenWidgetState();
}

class _DiceScreenWidgetState extends State<DiceScreenWidget> {
  bool _rollVirtualDice = true;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = info.buildNumber.isNotEmpty
            ? '${info.version}+${info.buildNumber}'
            : info.version;
      });
    } catch (_) {
      // ignore errors; version is optional UI detail
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(color: Colors.blue),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    if (_appVersion != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'v$_appVersion',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            AppSettingsWidget(vm: widget.settingsVm),
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
                      listenable: widget.settingsVm,
                      builder: (context, _) {
                        return TextButton.icon(
                          onPressed:
                              widget.settingsVm.bleIsEnabled()
                                  ? () {
                                    widget.settingsVm.startBleScan.execute();
                                  }
                                  : null,
                          label:
                              widget.settingsVm.bleIsEnabled()
                                  ? Text(kIsWeb ? "Pair Die" : "Scan")
                                  : Text("BLE Disabled"),
                          icon:
                              widget.settingsVm.bleIsEnabled()
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
                              return DieListTile(
                                die: die,
                                themeMode: widget.settingsVm.themeMode,
                                onTap: () => _showDieSettings(context, die),
                              );
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

  void _showDieSettings(BuildContext context, GenericDie die) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) => SingleDieSettingsDialog(
            die: die,
            haEnabled: widget.settingsVm.getHaConfig().enabled,
            onBlink: widget.viewModel.blink.execute,
            onDisconnect: widget.viewModel.disconnectDie.execute,
            onSave: widget.viewModel.updateDieSettings.execute,
          ),
        );
      },
    );
  }

  // Helpers
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

  Color _getBlinkColor(BuildContext context, GenericDie? die) {
    return die?.blinkColor?.withAlpha(255) ??
        Theme.of(context).textTheme.bodyMedium?.color! ??
        (widget.settingsVm.themeMode == ThemeMode.dark ? Colors.white : Colors.black);
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

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }
}
