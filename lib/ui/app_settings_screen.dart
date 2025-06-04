import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'dice_screen_vm.dart';

/// A widget that displays application-level settings including Bluetooth settings.
/// This widget can be included in screens that need to display app settings.
class AppSettingsWidget extends StatelessWidget {
  const AppSettingsWidget({super.key, required this.ips, required this.parentVm});

  final List<String> ips;
  final DiceScreenViewModel parentVm;

  void _showHomeAssistantSettings(BuildContext context, DiceScreenViewModel vm) async {
    var haConfig = vm.getHaConfig();
    final urlController = TextEditingController(text: haConfig.url);
    final tokenController = TextEditingController(text: haConfig.token);
    final entityController = TextEditingController(text: haConfig.entity);
    bool isEnabled = haConfig.enabled;
    bool webDisabled = kIsWeb && !isEnabled;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          // Use StatefulBuilder to manage toggle state
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Home Assistant Settings${webDisabled ? "\nDisabled On Web " : ""}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Enable Home Assistant'),
                      value: isEnabled,
                      onChanged:
                          webDisabled
                              ? null
                              : (bool value) {
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

  ListenableBuilder _makeBleScanButton(DiceScreenViewModel parentVm) {
    return ListenableBuilder(
      listenable: parentVm,
      builder: (context, _) {
        return ListTile(
          onTap:
              parentVm.bleIsEnabled()
                  ? () {
                    parentVm.startBleScan.execute();
                  }
                  : null,
          title: parentVm.bleIsEnabled() ? Text(kIsWeb ? "Pair Die" : "Scan") : Text("BLE Disabled"),
          leading:
              parentVm.bleIsEnabled() ? const Icon(Icons.bluetooth_searching) : const Icon(Icons.bluetooth_disabled),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Application Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Theme toggle
            ListenableBuilder(
              listenable: parentVm,
              builder: (context, _) {
                return ListTile(
                  leading: Icon(parentVm.themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
                  title: Text(parentVm.themeMode == ThemeMode.light ? 'Dark Mode' : 'Light Mode'),
                  onTap: () {
                    parentVm.toggleTheme.execute();
                    Navigator.pop(context);
                  },
                );
              },
            ),
            const Divider(),
            // Bluetooth settings section
            // const Text(
            //   'Connectivity',
            //   style: TextStyle(
            //     fontSize: 16,
            //     fontWeight: FontWeight.w500,
            //   ),
            // ),
            // const SizedBox(height: 8),
            // _buildPlatformSpecificBluetoothSetting(),
            //
            // const Divider(),

            // ListTile(
            //   title: const Text('Theme'),
            //   trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            //   leading: const Icon(Icons.color_lens),
            //   onTap: () {
            //     // Theme selection logic would be handled by the ViewModel
            //   },
            // ),
            ListenableBuilder(
              listenable: parentVm,
              builder: (context, _) {
                return ListTile(
                  title: Text(
                    'Bluetooth: ${parentVm.bleIsEnabled()
                        ? kIsWeb
                            ? "supported"
                            : "enabled"
                        : "disabled${kIsWeb ? "\nBLE only supported in Chrome" : ""}"}',
                    // 'Bluetooth: ${parentVm.bleIsEnabled() ? "enabled" : "disabled${kIsWeb ? "\nBLE only supported in Chrome" : ""}"}',
                  ),
                  // trailing: Text(bleEnabled ? "enabled" : kIsWeb ? "BLE only supported on Chrome" : "disabled"),
                  leading: parentVm.bleIsEnabled() ? const Icon(Icons.bluetooth) : const Icon(Icons.bluetooth_disabled),
                  enabled: parentVm.bleIsEnabled(),
                  onTap: () {
                    // About screen navigation would be handled by the ViewModel
                  },
                );
              },
            ),
            _makeBleScanButton(parentVm),
            ListTile(
              onTap:
                  parentVm.bleIsEnabled()
                      ? () {
                        parentVm.disconnectAllNonVirtualDice.execute();
                      }
                      : null,
              title: const Text("Disconnect Dice"),
              leading: const Icon(Icons.bluetooth_disabled),
            ),
            const Divider(),
            ListTile(
              title: const Text('API IPs'),
              trailing: Text(ips.join("\n")),
              leading: const Icon(Icons.info_outline),
              enabled: ips.isNotEmpty,
              onTap: () {
                // About screen navigation would be handled by the ViewModel
              },
            ),
            const Divider(),
            ListenableBuilder(
              listenable: parentVm,
              builder: (context, _) {
                return ListTile(
                  leading: const Icon(Icons.home),
                  title: Text('Home Assistant Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    _showHomeAssistantSettings(context, parentVm);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
