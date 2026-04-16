import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../di/di.dart';
import '../../services/app_service.dart';
import 'app_settings_screen_vm.dart';
import 'script_screen.dart';
import 'sound_clips_screen.dart';

/// A widget that displays application-level settings including Bluetooth settings.
/// This widget can be included in screens that need to display app settings.
class AppSettingsWidget extends StatelessWidget {
  const AppSettingsWidget({super.key, required this.vm});

  final AppSettingsScreenViewModel vm;

  static Future<AppSettingsWidget> create(DiWrapper di) async {
    var vm = AppSettingsScreenViewModel(di);
    var widget = AppSettingsWidget(vm: vm);

    return widget;
  }

  void _showHomeAssistantSettings(BuildContext context, AppSettingsScreenViewModel vm) async {
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
              title: Text(
                'Home Assistant Settings${kIsWeb ? "\nEnsure HA accepts rollfeathers.ungawatkt.com in CORs " : ""}',
              ),
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

  void _showLayoutOrientationDialog(BuildContext context, AppSettingsScreenViewModel vm) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Layout Orientation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: DicePaneOrientation.values.map((orientation) {
              return RadioListTile<DicePaneOrientation>(
                title: Text(orientation.name[0].toUpperCase() + orientation.name.substring(1)),
                value: orientation,
                groupValue: vm.dicePaneOrientation,
                onChanged: (DicePaneOrientation? value) {
                  if (value != null) {
                    vm.setDicePaneOrientation.execute(value);
                    Navigator.of(context).pop();
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  ListenableBuilder _makeBleScanButton(AppSettingsScreenViewModel vm) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final bool enableScan = kIsWeb || vm.bleIsEnabled();
        return ListTile(
          onTap: enableScan
              ? () {
                  vm.startBleScan.execute();
                }
              : null,
          title: enableScan ? Text(kIsWeb ? "Pair Die" : "Scan") : const Text("BLE Disabled"),
          leading: enableScan ? const Icon(Icons.bluetooth_searching) : const Icon(Icons.bluetooth_disabled),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Application', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            // Theme toggle
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                return ListTile(
                  leading: Icon(vm.themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
                  title: Text(vm.themeMode == ThemeMode.light ? 'Dark Mode' : 'Light Mode'),
                  onTap: () {
                    vm.toggleTheme.execute();
                    Navigator.pop(context);
                  },
                );
              },
            ),
            // Keep screen on toggle
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                return SwitchListTile(
                  secondary: Icon(vm.getKeepScreenOn() ? Icons.visibility : Icons.visibility_off),
                  title: const Text('Keep Screen On'),
                  value: vm.getKeepScreenOn(),
                  onChanged: (bool value) {
                    vm.toggleKeepScreenOn.execute();
                  },
                );
              },
            ),
            // Layout orientation
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                IconData icon;
                switch (vm.dicePaneOrientation) {
                  case DicePaneOrientation.auto:
                    icon = Icons.brightness_auto;
                    break;
                  case DicePaneOrientation.horizontal:
                    icon = Icons.view_column;
                    break;
                  case DicePaneOrientation.vertical:
                    icon = Icons.view_stream;
                    break;
                }
                return ListTile(
                  leading: Icon(icon),
                  title: const Text('Layout Orientation'),
                  subtitle: Text(
                    vm.dicePaneOrientation.name[0].toUpperCase() + vm.dicePaneOrientation.name.substring(1),
                  ),
                  onTap: () {
                    _showLayoutOrientationDialog(context, vm);
                  },
                );
              },
            ),
            const Divider(),
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                return ListTile(
                  title: Text(
                    'Bluetooth: ${vm.bleIsEnabled()
                        ? kIsWeb
                            ? "supported"
                            : "enabled"
                        : "disabled${kIsWeb ? "\nBLE only supported in Chrome" : ""}"}',
                    // 'Bluetooth: ${parentVm.bleIsEnabled() ? "enabled" : "disabled${kIsWeb ? "\nBLE only supported in Chrome" : ""}"}',
                  ),
                  // trailing: Text(bleEnabled ? "enabled" : kIsWeb ? "BLE only supported on Chrome" : "disabled"),
                  leading: vm.bleIsEnabled() ? const Icon(Icons.bluetooth) : const Icon(Icons.bluetooth_disabled),
                  enabled: vm.bleIsEnabled(),
                  onTap: () {
                    // About screen navigation would be handled by the ViewModel
                  },
                );
              },
            ),
            _makeBleScanButton(vm),
            ListTile(
              onTap:
                  vm.bleIsEnabled()
                      ? () {
                        vm.disconnectAllNonVirtualDice.execute();
                      }
                      : null,
              title: const Text("Disconnect BLE Dice"),
              leading: const Icon(Icons.bluetooth_disabled),
            ),
            const Divider(),
            ListTile(
              title: const Text('API IPs'),
              trailing: Text(vm.getIpAddresses().join("\n")),
              leading: const Icon(Icons.info_outline),
              enabled: vm.getIpAddresses().isNotEmpty,
              onTap: () {
                // About screen navigation would be handled by the ViewModel
              },
            ),
            const Divider(),
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                return ListTile(
                  leading: const Icon(Icons.home),
                  title: Text('Home Assistant Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    _showHomeAssistantSettings(context, vm);
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Rule Scripts'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => ScriptScreenWidget(viewModel: vm)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Sound Clips'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SoundClipsScreen(
                      repo: vm.soundClipRepository,
                      player: vm.soundClipPlayer,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
