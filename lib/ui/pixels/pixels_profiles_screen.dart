import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:roll_feathers/dice_sdks/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels_builtin_profiles.dart';
import 'package:roll_feathers/dice_sdks/pixels_profile_transfer.dart';
import 'package:roll_feathers/services/pixels/pixel_profile_store.dart';
import 'package:roll_feathers/ui/pixels/pixels_profile_editor_screen.dart';

int _profileHash(PixelProfile p) => PixelDataSet(p).computeHash();

/// Full-screen profile manager for a single Pixels die.
///
/// Lists all saved profiles, allows add/edit/delete, and transfers the active
/// profile to the physical die.
class PixelsProfilesScreen extends StatefulWidget {
  const PixelsProfilesScreen({
    super.key,
    required this.die,
    required this.dieName,
    required this.store,
  });

  final PixelsDieInterface die;
  final String dieName;
  final PixelProfileStore store;

  @override
  State<PixelsProfilesScreen> createState() => _PixelsProfilesScreenState();
}

class _PixelsProfilesScreenState extends State<PixelsProfilesScreen> {
  List<PixelProfile> _profiles = [];
  Map<String, int> _hashes = {}; // profileId → computed hash
  bool _loading = true;
  String? _transferring; // profile id being transferred
  String? _statusMessage;
  int? _dieHash; // hash currently on the die

  @override
  void initState() {
    super.initState();
    _dieHash = widget.die.currentDataSetHash;
    _load();
  }

  Future<void> _load() async {
    final profiles = await widget.store.loadAll();
    if (!mounted) return;
    final hashes = {for (final p in profiles) p.id: _profileHash(p)};
    setState(() {
      _profiles = profiles;
      _hashes = hashes;
      _loading = false;
    });
  }

  Future<void> _addProfile() async {
    final chosen = await showModalBottomSheet<PixelProfile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PresetPickerSheet(),
    );
    if (chosen == null) return;

    final withId = PixelProfile(
      id: const Uuid().v4(),
      name: chosen.name,
      brightness: chosen.brightness,
      animations: chosen.animations,
      rules: chosen.rules,
    );
    final saved = await _openEditor(withId);
    if (saved != null) {
      await widget.store.upsert(saved);
      await _load();
    }
  }

  Future<void> _editProfile(PixelProfile profile) async {
    final saved = await _openEditor(profile);
    if (saved != null) {
      await widget.store.upsert(saved);
      await _load();
    }
  }

  Future<PixelProfile?> _openEditor(PixelProfile profile) {
    return Navigator.of(context).push<PixelProfile>(
      MaterialPageRoute(
        builder: (_) => PixelsProfileEditorScreen(profile: profile),
      ),
    );
  }

  Future<void> _deleteProfile(PixelProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Delete "${profile.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.delete(profile.id);
      await _load();
    }
  }

  Future<void> _transferProfile(PixelProfile profile) async {
    setState(() { _transferring = profile.id; _statusMessage = null; });
    try {
      final transfer = PixelsProfileTransfer(widget.die);
      await transfer.transferProfile(profile);
      if (mounted) {
        setState(() {
          _transferring = null;
          _statusMessage = '✓ "${profile.name}" flashed to die';
          _dieHash = _hashes[profile.id];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transferring = null;
          _statusMessage = 'Transfer failed: $e';
        });
      }
    }
  }

  Future<void> _previewProfile(PixelProfile profile) async {
    setState(() { _transferring = profile.id; _statusMessage = null; });
    try {
      final transfer = PixelsProfileTransfer(widget.die);
      await transfer.transferInstantAnimation(profile);
      await transfer.playInstantAnimation(animIndex: 0, faceIndex: -1, loopCount: 1);
      if (mounted) setState(() { _transferring = null; _statusMessage = 'Preview sent'; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _transferring = null;
          _statusMessage = 'Preview failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Animations — ${widget.dieName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Profile',
            onPressed: _addProfile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_statusMessage != null)
                  Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(_statusMessage!)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _statusMessage = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _profiles.isEmpty
                      ? const Center(child: Text('No profiles yet.\nTap + to create one.', textAlign: TextAlign.center))
                      : ListView.builder(
                          itemCount: _profiles.length,
                          itemBuilder: (_, i) {
                            final p = _profiles[i];
                            final isTransferring = _transferring == p.id;
                            final isOnDie = _dieHash != null &&
                                _hashes[p.id] == _dieHash;
                            return ListTile(
                              title: Text(p.name),
                              subtitle: Row(
                                children: [
                                  Text(
                                    '${p.animations.length} animation${p.animations.length == 1 ? '' : 's'}'
                                    ' · ${p.rules.length} rule${p.rules.length == 1 ? '' : 's'}',
                                  ),
                                  if (isOnDie) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.check_circle,
                                        size: 14, color: Colors.green),
                                    const SizedBox(width: 2),
                                    Text('on die',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.green[700])),
                                  ],
                                ],
                              ),
                              trailing: isTransferring
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : _ProfileActions(
                                      onEdit: () => _editProfile(p),
                                      onPreview: () => _previewProfile(p),
                                      onFlash: () => _transferProfile(p),
                                      onDelete: () => _deleteProfile(p),
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.onEdit,
    required this.onPreview,
    required this.onFlash,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onFlash;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.play_circle_outline),
          tooltip: 'Preview on die',
          onPressed: onPreview,
        ),
        IconButton(
          icon: const Icon(Icons.upload),
          tooltip: 'Flash to die',
          onPressed: onFlash,
        ),
        PopupMenuButton<_Action>(
          onSelected: (a) => switch (a) {
            _Action.edit => onEdit(),
            _Action.delete => onDelete(),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: _Action.edit, child: Text('Edit')),
            PopupMenuItem(value: _Action.delete, child: Text('Delete')),
          ],
        ),
      ],
    );
  }
}

enum _Action { edit, delete }

// ─── Preset picker ────────────────────────────────────────────────────────────

class _PresetPickerSheet extends StatelessWidget {
  const _PresetPickerSheet();

  @override
  Widget build(BuildContext context) {
    final presets = kBuiltinProfiles;
    final blank = PixelProfile(
      id: '',
      name: 'New Profile',
      animations: [PixelAnimationSimple(durationMs: 500, color: const PixelColor(255, 0, 0), count: 1, fade: 128)],
      rules: [PixelRule(condition: PixelConditionRolled(), actions: [PixelActionPlayAnimation(animIndex: 0)])],
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Choose a starting point', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...presets.map((p) => ListTile(
                    leading: _presetIcon(p.name),
                    title: Text(p.name),
                    subtitle: Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, p.build()),
                  )),
                  const Divider(),
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.add, size: 18)),
                    title: const Text('Blank profile'),
                    subtitle: const Text('Start from scratch'),
                    onTap: () => Navigator.pop(context, blank),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetIcon(String name) {
    final (color, icon) = switch (name) {
      'High / Low'  => (Colors.green, Icons.trending_up),
      'Flashy'      => (Colors.purple, Icons.auto_awesome),
      'Rainbow'     => (Colors.orange, Icons.colorize),
      'Color Cycle' => (Colors.teal, Icons.loop),
      'Fire'        => (Colors.deepOrange, Icons.local_fire_department),
      'Magic'       => (Colors.indigo, Icons.auto_fix_high),
      'Empty'       => (Colors.grey, Icons.radio_button_unchecked),
      'Speak'       => (Colors.lightBlue, Icons.record_voice_over),
      'Waterfall'   => (Colors.cyan, Icons.water),
      'Fountain'    => (Colors.lightBlue, Icons.waves),
      'Spinning'    => (Colors.amber, Icons.refresh),
      'Spiral'      => (Colors.lime, Icons.tornado),
      'Noise'       => (Colors.blueGrey, Icons.grain),
      'Worm'        => (Colors.lightGreen, Icons.linear_scale),
      'Rose'        => (Colors.pink, Icons.local_florist),
      'Water'       => (Colors.blue, Icons.water_drop),
      _             => (Colors.blue, Icons.star),
    };
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
