
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/repositories/dddice_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/services/dddice/dddice_config_service.dart';
import 'package:roll_feathers/ui/app_settings/app_settings_screen_vm.dart';
import 'package:roll_feathers/ui/app_settings/script_screen.dart';

// ---------------------------------------------------------------------------
// dddice settings dialog
// ---------------------------------------------------------------------------

enum DddiceDialogState { unauthenticated, activating, authenticated }

class DddiceSettingsContent extends StatefulWidget {
  final AppSettingsScreenViewModel vm;
  const DddiceSettingsContent({super.key, required this.vm});

  @override
  State<DddiceSettingsContent> createState() => DddiceSettingsContentState();
}

class DddiceSettingsContentState extends State<DddiceSettingsContent> {
  late DddiceConfig _config;
  DddiceDialogState _dialogState = DddiceDialogState.unauthenticated;

  // activation flow — only the code string for display; polling is in the domain
  DddiceActivationCode? _activationCode;

  // dropdown data
  List<DddiceRoom>? _rooms;
  List<DddiceTheme>? _themes;
  bool _loadingRooms = false;
  bool _loadingThemes = false;
  String? _error;

  final TextEditingController _roomCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _config = widget.vm.getDddiceConfig();
    widget.vm.addListener(_onVmUpdate);
    if (_config.isAuthenticated) {
      _dialogState = DddiceDialogState.authenticated;
      _loadDropdowns();
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onVmUpdate);
    _roomCodeController.dispose();
    super.dispose();
  }

  void _onVmUpdate() {
    if (!mounted) return;
    final newConfig = widget.vm.getDddiceConfig();
    if (_dialogState == DddiceDialogState.activating) {
      if (newConfig.isAuthenticated) {
        setState(() {
          _config = newConfig;
          _activationCode = null;
          _dialogState = DddiceDialogState.authenticated;
          _rooms = null;
          _themes = null;
          _error = null;
        });
        _saveEnabled(true);
        _loadDropdowns();
      } else {
        final err = widget.vm.activationError;
        if (err != null) setState(() { _error = err; });
      }
    }
  }

  Future<void> _loadDropdowns() async {
    if (!_config.isAuthenticated) return;
    setState(() {
      _loadingRooms = true;
      _loadingThemes = !_config.isGuest;
    });
    try {
      final rooms = await widget.vm.dddiceListRooms();
      if (mounted) setState(() { _rooms = rooms; _loadingRooms = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingRooms = false; });
    }
    if (!_config.isGuest) {
      try {
        final themes = await widget.vm.dddiceListThemes();
        if (mounted) setState(() { _themes = themes; _loadingThemes = false; });
      } catch (_) {
        if (mounted) setState(() { _loadingThemes = false; });
      }
    }
  }

  Future<void> _startGuestAuth() async {
    setState(() { _error = null; });
    final success = await widget.vm.dddiceSignInAsGuest();
    if (!mounted) return;
    if (!success) {
      setState(() { _error = 'Failed to create guest account. Please try again.'; });
      return;
    }
    await _saveEnabled(true);
    if (!mounted) return;
    setState(() {
      _config = widget.vm.getDddiceConfig();
      _dialogState = DddiceDialogState.authenticated;
      _rooms = null;
      _themes = null;
    });
    _loadDropdowns();
  }

  Future<void> _startActivation() async {
    setState(() { _error = null; });
    final code = await widget.vm.dddiceStartActivation();
    if (!mounted) return;
    if (code == null) {
      setState(() { _error = 'Failed to start activation. Please try again.'; });
      return;
    }
    setState(() {
      _activationCode = code;
      _dialogState = DddiceDialogState.activating;
    });
    // Polling and config-save happen in the domain; _onVmUpdate() drives the
    // state transition when activation completes.
  }

  Future<void> _signOut() async {
    await widget.vm.dddiceSignOut();
    if (!mounted) return;
    setState(() {
      _config = const DddiceConfig();
      _activationCode = null;
      _dialogState = DddiceDialogState.unauthenticated;
      _rooms = null;
      _themes = null;
      _error = null;
    });
  }

  Future<void> _saveEnabled(bool value) async {
    final updated = _config.copyWith(enabled: value);
    await widget.vm.saveDddiceConfig(updated);
    setState(() { _config = updated; });
  }

  Future<void> _saveRoom(DddiceRoom room) async {
    final updated = _config.copyWith(roomSlug: room.slug, roomName: room.name);
    await widget.vm.saveDddiceConfig(updated);
    setState(() { _config = updated; });
  }

  // Returns dropdown items for the room picker. If the configured room slug is
  // not in the fetched list (e.g. fresh guest session), injects it as a
  // synthetic entry so the current selection remains visible.
  List<DropdownMenuItem<String>> _roomDropdownItems() {
    final fetched = _rooms ?? [];
    final hasConfiguredRoom = _config.roomSlug.isNotEmpty;
    final configuredInList = fetched.any((r) => r.slug == _config.roomSlug);
    return [
      if (hasConfiguredRoom && !configuredInList)
        DropdownMenuItem(
          value: _config.roomSlug,
          child: Text(DddiceRoom(slug: _config.roomSlug, name: _config.roomName).displayName),
        ),
      ...fetched.map((r) => DropdownMenuItem(value: r.slug, child: Text(r.displayName))),
    ];
  }

  Future<void> _saveRoomCode(String code) async {
    final slug = code.trim();
    if (slug.isEmpty) return;
    await _saveRoom(DddiceRoom(slug: slug, name: slug));
    _roomCodeController.clear();
  }

  Future<void> _saveTheme(DddiceTheme theme) async {
    final updated = _config.copyWith(themeId: theme.id, themeName: theme.name);
    await widget.vm.saveDddiceConfig(updated);
    setState(() { _config = updated; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text('dddice Settings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          if (_config.needsReauth && _dialogState == DddiceDialogState.authenticated) ...[
            Container(
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(children: [
                const Icon(Icons.warning_amber),
                const SizedBox(width: 8),
                Expanded(child: Text('Session expired. Please sign in again.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          ..._buildBody(context),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    switch (_dialogState) {
      case DddiceDialogState.unauthenticated:
        return _buildUnauthenticated();
      case DddiceDialogState.activating:
        return _buildActivating();
      case DddiceDialogState.authenticated:
        return _buildAuthenticated();
    }
  }

  List<Widget> _buildUnauthenticated() => [
        const Text('Connect to dddice to mirror your rolls as 3D animations for remote players.'),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with dddice'),
              onPressed: _startActivation,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_outline),
              label: const Text('Use guest account'),
              onPressed: _startGuestAuth,
            ),
          ],
        ),
      ];

  List<Widget> _buildActivating() {
    final code = _activationCode?.code ?? '';
    return [
      const Text('Enter this code at dddice.com/activate:'),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Open dddice.com/activate'),
        onPressed: () => launchUrl(
          Uri.parse('https://dddice.com/activate'),
          mode: LaunchMode.externalApplication,
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                code,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      fontFeatures: [const FontFeature.slashedZero()],
                    ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied to clipboard'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        const Text('Waiting for activation...'),
      ]),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () async {
          await widget.vm.dddiceCancelActivation();
          if (!mounted) return;
          setState(() {
            _activationCode = null;
            _dialogState = DddiceDialogState.unauthenticated;
            _error = null;
          });
        },
        child: const Text('Cancel'),
      ),
    ];
  }

  List<Widget> _buildAuthenticated() => [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable dddice'),
          value: _config.enabled,
          onChanged: _saveEnabled,
        ),
        const Divider(),
        Row(children: [
          Expanded(
            child: Text(
              _config.isGuest ? 'Signed in as guest' : 'Signed in',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ]),
        const SizedBox(height: 8),
        // Room picker
        Row(children: [
          const Expanded(flex: 2, child: Text('Room')),
          Expanded(
            flex: 5,
            child: _loadingRooms
                ? const Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Select room'),
                    value: _config.roomSlug.isNotEmpty ? _config.roomSlug : null,
                    items: _roomDropdownItems(),
                    onChanged: (slug) {
                      final allRooms = [
                        ...(_rooms ?? []),
                        if (_config.roomSlug.isNotEmpty &&
                            !(_rooms ?? []).any((r) => r.slug == _config.roomSlug))
                          DddiceRoom(slug: _config.roomSlug, name: _config.roomName.isNotEmpty ? _config.roomName : _config.roomSlug),
                      ];
                      final room = allRooms.firstWhere((r) => r.slug == slug);
                      _saveRoom(room);
                    },
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _loadDropdowns,
            tooltip: 'Refresh',
          ),
        ]),
        // Room link
        if (_config.roomSlug.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 0, bottom: 4),
            child: Row(children: [
              const Expanded(flex: 2, child: SizedBox.shrink()),
              Expanded(
                flex: 5,
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse('https://dddice.com/room/${_config.roomSlug}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    'Open room on dddice.com',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ]),
          ),
        // Manual room code entry
        Row(children: [
          const Expanded(flex: 2, child: Text('')),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _roomCodeController,
              decoration: const InputDecoration(
                hintText: 'or enter room code…',
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: _saveRoomCode,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 18),
            onPressed: () => _saveRoomCode(_roomCodeController.text),
            tooltip: 'Set room',
          ),
        ]),
        // Theme picker (hidden for guests)
        if (!_config.isGuest) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(flex: 2, child: Text('Theme')),
            Expanded(
              flex: 5,
              child: _loadingThemes
                  ? const Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                  : DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('Select theme'),
                      value: _config.themeId.isNotEmpty ? _config.themeId : null,
                      items: (_themes ?? [])
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                          .toList(),
                      onChanged: (id) {
                        final theme = (_themes ?? []).firstWhere((t) => t.id == id);
                        _saveTheme(theme);
                      },
                    ),
            ),
            const SizedBox(width: 40), // align with room row refresh button
          ]),
        ] else ...[
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(flex: 2, child: Text('Theme')),
            const Expanded(flex: 5, child: Text('dddice-bees (guest default)')),
            const SizedBox(width: 40),
          ]),
        ],
      ];
}

// ---------------------------------------------------------------------------

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
                'Home Assistant Settings${vm.isWeb ? "\nEnsure HA accepts rollfeathers.ungawatkt.com in CORs " : ""}',
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
        final bool enableScan = vm.isWeb || vm.bleIsEnabled();
        return ListTile(
          onTap: enableScan
              ? () {
                  vm.startBleScan.execute();
                }
              : null,
          title: enableScan ? Text(vm.isWeb ? "Pair Die" : "Scan") : const Text("BLE Disabled"),
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
                        ? vm.isWeb
                            ? "supported"
                            : "enabled"
                        : "disabled${vm.isWeb ? "\nBLE only supported in Chrome" : ""}"}',
                  ),
                  leading: vm.bleIsEnabled() ? const Icon(Icons.bluetooth) : const Icon(Icons.bluetooth_disabled),
                  enabled: vm.bleIsEnabled(),
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
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                final cfg = vm.getDddiceConfig();
                String subtitle;
                if (!cfg.isAuthenticated) {
                  subtitle = 'Not configured';
                } else {
                  final who = cfg.isGuest ? 'Guest' : 'Signed in';
                  final room = cfg.roomName.isNotEmpty ? ' · ${cfg.roomName}' : '';
                  final theme = (!cfg.isGuest && cfg.themeName.isNotEmpty) ? ' · ${cfg.themeName}' : '';
                  subtitle = '$who$room$theme';
                }
                return ListTile(
                  leading: const Icon(Icons.casino),
                  title: const Text('dddice Settings'),
                  subtitle: Text(subtitle),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: DddiceSettingsContent(vm: vm),
                        ),
                      ),
                    );
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
            const Divider(),
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) {
                return SwitchListTile(
                  secondary: const Icon(Icons.webhook),
                  title: Row(
                    children: [
                      const Flexible(child: Text('Webhooks')),
                      if (vm.isWeb) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'CORS preflight (OPTIONS) must be supported by the target server for JSON payloads.',
                          child: const Icon(Icons.info_outline, size: 16),
                        ),
                      ],
                    ],
                  ),
                  value: vm.webhooksEnabled,
                  onChanged: (bool value) {
                    vm.toggleWebhooksEnabled.execute();
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
