// File: lib/ui/widgets/app_settings_widget.dart

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A widget that displays application-level settings including Bluetooth settings.
/// This widget can be included in screens that need to display app settings.
class AppSettingsWidget extends StatelessWidget {
  const AppSettingsWidget({
    super.key,
    this.onBluetoothToggled,
    this.isBluetoothEnabled = false,
    this.onOpenBluetoothSettings, // do this more correctly
    required this.ips,
    required this.bleEnabled,
  });

  final List<String> ips;
  final bool bleEnabled;

  /// Callback when Bluetooth is toggled
  final Function(bool)? onBluetoothToggled;

  /// Current Bluetooth state
  final bool isBluetoothEnabled;

  /// Callback to open system Bluetooth settings
  final VoidCallback? onOpenBluetoothSettings;

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
            ListTile(
              title: Text(
                'Bluetooth: ${bleEnabled ? "enabled" : "disabled${kIsWeb ? "\nBLE only supported in Chrome" : ""}"}',
              ),
              // trailing: Text(bleEnabled ? "enabled" : kIsWeb ? "BLE only supported on Chrome" : "disabled"),
              leading: bleEnabled ? const Icon(Icons.bluetooth) : const Icon(Icons.bluetooth_disabled),
              enabled: bleEnabled,
              onTap: () {
                // About screen navigation would be handled by the ViewModel
              },
            ),
            ListTile(
              title: const Text('IPs'),
              trailing: Text(ips.join("\n")),
              leading: const Icon(Icons.info_outline),
              enabled: ips.isNotEmpty,
              onTap: () {
                // About screen navigation would be handled by the ViewModel
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the appropriate Bluetooth setting widget based on platform
  Widget _buildPlatformSpecificBluetoothSetting() {
    // For web, we'll show a message that Bluetooth might not be available
    if (kIsWeb) {
      return ListTile(
        title: const Text('Bluetooth'),
        subtitle: const Text('Bluetooth access may be limited in web browsers'),
        leading: const Icon(Icons.bluetooth_disabled, color: Colors.grey),
      );
    }

    // For iOS, macOS, and other platforms where direct toggle isn't appropriate
    if (Platform.isIOS || Platform.isMacOS) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: () {
              print('Opening Bluetooth settings');
              onOpenBluetoothSettings?.call();
            },
            child: const Text('Open Bluetooth Settings'),
          ), // ListTile(
          //   title: const Text('Bluetooth'),
          //   subtitle:
          //   leading: Icon(
          //     Icons.bluetooth,
          //     color: isBluetoothEnabled ? Colors.blue : Colors.grey,
          //   ),
          // ),
          // Padding(
          //   padding: const EdgeInsets.only(left: 72.0, right: 16.0, bottom: 16.0),
          //   child: ElevatedButton(
          //     onPressed: onOpenBluetoothSettings,
          //     child: const Text('Open System Settings'),
          //   ),
          // ),
        ],
      );
    }

    // For Android and other platforms that support direct Bluetooth toggle
    return SwitchListTile(
      title: const Text('Bluetooth'),
      subtitle: Text(isBluetoothEnabled ? 'On' : 'Off'),
      value: isBluetoothEnabled,
      onChanged: onBluetoothToggled,
      secondary: Icon(Icons.bluetooth, color: isBluetoothEnabled ? Colors.blue : Colors.grey),
    );
  }
}
