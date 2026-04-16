import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domains/sound/sound_clip.dart';
import '../../domains/sound/sound_clip_player.dart';
import '../../domains/sound/sound_clip_repository.dart';
import '../../domains/sound/sound_settings.dart';

class SoundClipsScreen extends StatefulWidget {
  final SoundClipRepository repo;
  final SoundClipPlayer player;

  const SoundClipsScreen({super.key, required this.repo, required this.player});

  @override
  State<SoundClipsScreen> createState() => _SoundClipsScreenState();
}

class _SoundClipsScreenState extends State<SoundClipsScreen> {
  List<SoundClip> _clips = [];
  SoundSettings _settings = SoundSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clips = await widget.repo.getClips();
    final settings = await widget.repo.getSettings();
    if (mounted) {
      setState(() {
        _clips = clips;
        _settings = settings;
        _loading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    await widget.repo.saveSettings(_settings);
  }

  Future<void> _addClip() async {
    final result = await FilePicker.pickFiles(type: FileType.audio, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final defaultName = file.name.contains('.')
        ? file.name.substring(0, file.name.lastIndexOf('.'))
        : file.name;

    if (!mounted) return;
    final name = await _showNameDialog(defaultName);
    if (name == null || name.trim().isEmpty) return;

    await widget.repo.importClip(file.path!, name.trim());
    await _load();
  }

  Future<void> _deleteClip(SoundClip clip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete clip?'),
        content: Text('Remove "${clip.name}" from the library?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    // Clear global sound selections if they reference this clip
    if (_settings.rollingClipId == clip.id || _settings.rolledClipId == clip.id) {
      if (_settings.rollingClipId == clip.id) _settings.rollingClipId = null;
      if (_settings.rolledClipId == clip.id) _settings.rolledClipId = null;
      await _saveSettings();
    }

    await widget.repo.deleteClip(clip.id);
    await _load();
  }

  Future<void> _renameClip(SoundClip clip) async {
    final name = await _showNameDialog(clip.name);
    if (name == null || name.trim().isEmpty || name.trim() == clip.name) return;
    await widget.repo.renameClip(clip.id, name.trim());
    await _load();
  }

  Future<String?> _showNameDialog(String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clip name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. victory_fanfare'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _pickClip({required bool forRolling}) async {
    final clip = await showDialog<SoundClip?>(
      context: context,
      builder: (ctx) => _ClipPickerDialog(clips: _clips),
    );
    // null means cancel; _ClipPickerDialog returns the SoundClip or a sentinel
    // We use a special "none" return via a dedicated value — handled below.
    if (!mounted) return;
    setState(() {
      if (forRolling) {
        _settings.rollingClipId = clip?.id;
      } else {
        _settings.rolledClipId = clip?.id;
      }
    });
    await _saveSettings();
  }

  String _clipNameById(String? id) {
    if (id == null) return 'None';
    return _clips.firstWhere((c) => c.id == id, orElse: () => SoundClip(id: '', name: '(deleted)', extension: '')).name;
  }

  Widget _buildQueueDepthRow() {
    return Row(
      children: [
        const Expanded(child: Text('Queue Depth')),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: _settings.queueDepth > 1
              ? () async {
                  setState(() => _settings.queueDepth--);
                  await _saveSettings();
                }
              : null,
        ),
        SizedBox(
          width: 32,
          child: Text('${_settings.queueDepth}', textAlign: TextAlign.center),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () async {
            setState(() => _settings.queueDepth++);
            await _saveSettings();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sound Clips')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Settings ─────────────────────────────────────────────────────
          Text('Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Hard Mute'),
            subtitle: const Text('Silence all sounds including rule clips'),
            value: _settings.hardMute,
            onChanged: (v) async {
              setState(() => _settings.hardMute = v);
              await _saveSettings();
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Rolling Sound'),
            subtitle: const Text('Plays once when a roll starts'),
            value: _settings.rollingEnabled,
            onChanged: (v) async {
              setState(() => _settings.rollingEnabled = v);
              await _saveSettings();
            },
          ),
          if (_settings.rollingEnabled)
            ListTile(
              title: const Text('Rolling Clip'),
              trailing: Text(_clipNameById(_settings.rollingClipId)),
              onTap: () => _pickClip(forRolling: true),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Rolled Sound'),
            subtitle: const Text('Plays when dice settle (if no rule clip fires)'),
            value: _settings.rolledEnabled,
            onChanged: (v) async {
              setState(() => _settings.rolledEnabled = v);
              await _saveSettings();
            },
          ),
          if (_settings.rolledEnabled)
            ListTile(
              title: const Text('Rolled Clip'),
              trailing: Text(_clipNameById(_settings.rolledClipId)),
              onTap: () => _pickClip(forRolling: false),
            ),
          const Divider(),
          _buildQueueDepthRow(),
          const SizedBox(height: 24),

          // ── Library ───────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text('Library', style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: _addClip,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_clips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('No clips yet. Tap Add to import an audio file.')),
            )
          else
            ..._clips.map(
              (clip) => ListTile(
                title: GestureDetector(
                  onTap: () => _renameClip(clip),
                  child: Text(clip.name),
                ),
                subtitle: Text(clip.extension.toUpperCase()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Preview',
                      onPressed: () => widget.player.previewClip(clip.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _deleteClip(clip),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dialog for picking a clip (or "None") for the global rolling/rolled sound slots.
class _ClipPickerDialog extends StatelessWidget {
  final List<SoundClip> clips;
  const _ClipPickerDialog({required this.clips});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Choose clip'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('None'),
        ),
        ...clips.map(
          (c) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, c),
            child: Text(c.name),
          ),
        ),
      ],
    );
  }
}
