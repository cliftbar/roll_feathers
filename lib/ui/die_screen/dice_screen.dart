import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen_vm.dart';
import 'package:roll_feathers/ui/die_screen/die_list_tile.dart';
import 'package:roll_feathers/ui/die_screen/single_die_settings_dialog.dart';

import 'package:roll_feathers/ui/app_settings/app_settings_screen.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';

class DiceScreenWidget extends StatefulWidget {
  const DiceScreenWidget({super.key, required this.viewModel, required this.settingsVm, required this.appVersion});

  static Future<DiceScreenWidget> create(DiWrapper di, AppSettingsScreenViewModel settingsVm) async {
    var vm = DiceScreenViewModel(di);
    return DiceScreenWidget(viewModel: vm, settingsVm: settingsVm, appVersion: di.appVersion);
  }

  final DiceScreenViewModel viewModel;
  final AppSettingsScreenViewModel settingsVm;
  final String appVersion;

  @override
  State<DiceScreenWidget> createState() => _DiceScreenWidgetState();
}

class _DiceScreenWidgetState extends State<DiceScreenWidget> {
  bool _rollVirtualDice = true;

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
                    if (widget.appVersion.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'v${widget.appVersion}',
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
                        widget.viewModel.removeAllVirtualDice.execute();
                      },
                      title: const Text('Remove Virtual Dice'),
                      leading: const Icon(Icons.remove_circle_outline),
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
      body: ListenableBuilder(
        listenable: widget.settingsVm,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final orientation = widget.settingsVm.dicePaneOrientation;
              final isNarrow = constraints.maxWidth < 600;
              final isShort = constraints.maxHeight < 400;

              final bool forceVertical = orientation == DicePaneOrientation.vertical;
              final bool forceHorizontal = orientation == DicePaneOrientation.horizontal;

              if (forceVertical || (isNarrow && !forceHorizontal)) {
                if (isShort) {
                  // Extremely cramped or forced vertical: Use a single scrollable view for everything.
                  return ListView(
                    key: const Key('dice_screen_compact_layout'),
                    children: [
                      _buildDiceColumn(isExpanded: false),
                      _buildHistoryColumn(isVertical: true, isExpanded: false),
                    ],
                  );
                } else {
                  // Narrow but tall or forced vertical: Stack them as two expanded panes.
                  return Column(
                    key: const Key('dice_screen_vertical_layout'),
                    children: [
                      Expanded(child: _buildDiceColumn()),
                      Expanded(child: _buildHistoryColumn(isVertical: true)),
                    ],
                  );
                }
              } else {
                // Wide screen or forced horizontal: Side-by-side panes.
                return Row(
                  key: const Key('dice_screen_horizontal_layout'),
                  children: [
                    Expanded(child: _buildDiceColumn()),
                    Expanded(child: _buildHistoryColumn(isVertical: false)),
                  ],
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildDiceColumn({bool isExpanded = true}) {
    return Column(
      children: [
        _buildDiceHeader(),
        isExpanded
            ? Expanded(child: _buildDiceList())
            : _buildDiceList(shrinkWrap: true, physics: const NeverScrollableScrollPhysics()),
      ],
    );
  }

  Widget _buildDiceHeader() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
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
            final bleOn = widget.settingsVm.bleIsEnabled();
            final scanning = widget.settingsVm.isScanning;
            return TextButton.icon(
              onPressed:
                  bleOn && !scanning
                      ? () {
                        widget.settingsVm.startBleScan.execute();
                      }
                      : null,
              label: bleOn ? Text(kIsWeb ? "Pair Die" : "Scan") : const Text("BLE Disabled"),
              icon:
                  scanning
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : bleOn
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
    );
  }

  Widget _buildDiceList({bool shrinkWrap = false, ScrollPhysics? physics}) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        return StreamBuilder<Map<String, GenericDie>>(
          stream: widget.viewModel.getDeviceStream(),
          initialData: widget.viewModel.dice,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final List<GenericDie> devices = snapshot.data?.values.toList() ?? [];

            if (devices.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(child: Text('No dice added')),
              );
            }
            return ListView.builder(
              shrinkWrap: shrinkWrap,
              physics: physics,
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
    );
  }

  Widget _buildHistoryColumn({required bool isVertical, bool isExpanded = true}) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: isVertical ? BorderSide.none : BorderSide(color: Colors.grey.shade300, width: 1),
          top: isVertical ? BorderSide(color: Colors.grey.shade300, width: 1) : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          _buildHistoryHeader(),
          isExpanded
              ? Expanded(child: _buildHistoryList())
              : _buildHistoryList(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Column(
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
      ],
    );
  }

  Widget _buildHistoryList({bool shrinkWrap = false, ScrollPhysics? physics}) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        return StreamBuilder(
          stream: widget.viewModel.getResultsStream(),
          initialData: widget.viewModel.rollHistory,
          builder: (context, snapshot) {
            List<RollResult> rollResults = snapshot.data ?? [];
            if (rollResults.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(child: Text('Make some rolls!')),
              );
            }
            return ListView.builder(
              shrinkWrap: shrinkWrap,
              physics: physics,
              itemCount: rollResults.length,
              itemBuilder: (context, index) {
                return ListTile(title: _makeRollText(context, rollResults[index]));
              },
            );
          },
        );
      },
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
            onPreviewRolling: widget.viewModel.previewRollingFlash.execute,
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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
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
    final nameController = TextEditingController(text: "");
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
