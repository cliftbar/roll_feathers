import 'package:flutter/material.dart';

import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/ui/pixels/pixels_profile_editor_screen.dart';
import 'package:roll_feathers/ui/pixels/pixels_profiles_screen_vm.dart';

class PixelsProfilesScreen extends StatefulWidget {
  const PixelsProfilesScreen({super.key, required this.viewModel});

  /// Builds the screen with a [PixelsProfilesScreenViewModel] for [dieService].
  static PixelsProfilesScreen create(
    PixelProfileDomain domain,
    PixelDieService dieService,
    String dieName,
  ) =>
      PixelsProfilesScreen(
        viewModel: PixelsProfilesScreenViewModel(domain, dieService, dieName),
      );

  final PixelsProfilesScreenViewModel viewModel;

  @override
  State<PixelsProfilesScreen> createState() => _PixelsProfilesScreenState();
}

class _PixelsProfilesScreenState extends State<PixelsProfilesScreen> {
  PixelsProfilesScreenViewModel get _vm => widget.viewModel;

  // View-only state (the rest lives in the ViewModel).
  bool _builtinsExpanded = true;
  bool _myProfilesExpanded = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Navigation (build the profile via the VM, open the editor, save) ───────

  Future<void> _addProfile() async {
    final chosen = await showModalBottomSheet<PixelProfile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PresetPickerSheet(),
    );
    if (chosen == null || !mounted) return;
    final saved = await _openEditor(_vm.newFromTemplate(chosen));
    if (saved != null) await _vm.saveEdited.execute(saved);
  }

  Future<void> _editProfile(PixelProfile profile) async {
    final saved = await _openEditor(profile);
    if (saved != null) await _vm.saveEdited.execute(saved);
  }

  /// Clones [profile] (deep copy, fresh id, "(copy)" name) and opens it in the
  /// editor so it can be tweaked before saving.
  Future<void> _duplicateProfile(PixelProfile profile) async {
    final saved = await _openEditor(_vm.duplicate(profile));
    if (saved != null) await _vm.saveEdited.execute(saved);
  }

  Future<PixelProfile?> _openEditor(PixelProfile profile) {
    return Navigator.of(context).push<PixelProfile>(
      MaterialPageRoute(
        builder: (_) => PixelsProfileEditorScreen.create(_vm.domain, _vm.dieService, profile),
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
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _vm.deleteProfile.execute(profile);
  }

  // ─── Rule/event helpers ───────────────────────────────────────────────────

  List<Widget> _ruleRows(PixelProfile profile, String transferId) {
    final rows = <Widget>[];
    for (final rule in profile.rules) {
      for (final action in rule.actions) {
        if (action is! PixelActionPlayAnimation) continue;
        final idx = action.animIndex;
        if (idx < 0 || idx >= profile.animations.length) continue;
        final anim = profile.animations[idx];
        final label = _conditionLabel(rule.condition);
        final color = _conditionColor(rule.condition);
        rows.add(ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 32, right: 8),
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(_conditionIcon(rule.condition), size: 14, color: color),
          ),
          title: Text(label),
          subtitle: Row(
            children: [
              _animIcon(anim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_animTypeName(anim)} · ${_animSubtitle(anim)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.play_circle_outline, size: 20),
            tooltip: 'Preview: $label',
            onPressed: _vm.transferringId != null
                ? null
                : () => _vm.previewAnimation.execute(profile, transferId, idx),
          ),
        ));
      }
    }
    return rows;
  }

  String _conditionLabel(PixelCondition c) => switch (c) {
    PixelConditionHelloGoodbye h =>
        h.flags == 1 ? 'Hello' : h.flags == 2 ? 'Goodbye' : 'Hello / Goodbye',
    PixelConditionHandling _ => 'Handling',
    PixelConditionRolling _ => 'Rolling',
    PixelConditionRolled r => 'Rolled · ${_faceMaskDesc(r.faceMask)}',
    PixelConditionCrooked _ => 'Crooked',
    PixelConditionConnectionState s =>
        s.flags == 1 ? 'Connected' : s.flags == 2 ? 'Disconnected' : 'Connection',
    PixelConditionBatteryState b => _batteryLabel(b),
    _ => c.displayName,
  };

  String _batteryLabel(PixelConditionBatteryState b) => const {
    1: 'Low battery',
    2: 'Charging',
    4: 'Charged',
    8: 'Bad charging',
    16: 'Charge error',
  }[b.flags] ?? 'Battery';

  String _faceMaskDesc(int mask) {
    if (mask >= 0xFFFFF) return 'any face';
    final faces = [for (var i = 0; i < 20; i++) if (mask & (1 << i) != 0) i + 1];
    if (faces.isEmpty) return 'no faces';
    if (faces.length == 1) return 'face ${faces.first}';
    final isRange = faces.last - faces.first == faces.length - 1;
    if (isRange) return 'faces ${faces.first}–${faces.last}';
    if (faces.length <= 4) return 'faces ${faces.join(', ')}';
    return '${faces.length} faces';
  }

  IconData _conditionIcon(PixelCondition c) => switch (c) {
    PixelConditionHelloGoodbye _ => Icons.waving_hand,
    PixelConditionHandling _ => Icons.pan_tool,
    PixelConditionRolling _ => Icons.casino,
    PixelConditionRolled _ => Icons.stop_circle,
    PixelConditionCrooked _ => Icons.screen_rotation,
    PixelConditionConnectionState _ => Icons.bluetooth,
    PixelConditionBatteryState _ => Icons.battery_charging_full,
    _ => Icons.help_outline,
  };

  Color _conditionColor(PixelCondition c) => switch (c) {
    PixelConditionHelloGoodbye _ => Colors.green,
    PixelConditionHandling _ => Colors.orange,
    PixelConditionRolling _ => Colors.blue,
    PixelConditionRolled _ => Colors.purple,
    PixelConditionCrooked _ => Colors.red,
    PixelConditionConnectionState _ => Colors.teal,
    PixelConditionBatteryState _ => Colors.amber,
    _ => Colors.grey,
  };

  Widget _animIcon(PixelAnimation anim) {
    final (color, icon) = switch (anim) {
      PixelAnimationSimple _          => (Colors.orange, Icons.flash_on),
      PixelAnimationRainbow _         => (Colors.purple, Icons.gradient),
      PixelAnimationGradient _        => (Colors.blue, Icons.water),
      PixelAnimationCycle _           => (Colors.teal, Icons.loop),
      PixelAnimationNoise _           => (Colors.blueGrey, Icons.grain),
      PixelAnimationNormals _         => (Colors.lightBlue, Icons.transform),
      PixelAnimationSequence _        => (Colors.amber, Icons.queue_play_next),
      PixelAnimationKeyframed _       => (Colors.deepPurple, Icons.timeline),
      PixelAnimationGradientPattern _ => (Colors.cyan, Icons.gradient),
      _                               => (Colors.grey, Icons.star),
    };
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, size: 14, color: color),
    );
  }

  String _animTypeName(PixelAnimation anim) => switch (anim) {
    PixelAnimationSimple _          => 'Solid Flash',
    PixelAnimationRainbow _         => 'Rainbow',
    PixelAnimationGradient _        => 'Flow',
    PixelAnimationCycle _           => 'Color Cycle',
    PixelAnimationNoise _           => 'Noise',
    PixelAnimationNormals _         => 'Normals',
    PixelAnimationSequence _        => 'Sequence',
    PixelAnimationKeyframed _       => 'Keyframed',
    PixelAnimationGradientPattern _ => 'Gradient Pattern',
    _                               => 'Custom',
  };

  String _animSubtitle(PixelAnimation anim) => switch (anim) {
    PixelAnimationSimple s          => '${s.durationMs}ms · rgb(${s.color.r},${s.color.g},${s.color.b}) · ×${s.count}',
    PixelAnimationRainbow r         => '${r.durationMs}ms · intensity ${r.intensity}',
    PixelAnimationGradient g        => '${g.durationMs}ms · flow',
    PixelAnimationCycle c           => '${c.durationMs}ms · intensity ${c.intensity}',
    PixelAnimationNoise n           => '${n.durationMs}ms · noise',
    PixelAnimationNormals n         => '${n.durationMs}ms · directional',
    PixelAnimationSequence s        => '${s.entries.length} part${s.entries.length == 1 ? '' : 's'}',
    PixelAnimationKeyframed k       => '${k.durationMs}ms · ${k.pattern?.name ?? 'no pattern'}',
    PixelAnimationGradientPattern g => '${g.durationMs}ms · ${g.pattern?.name ?? 'no pattern'}',
    _                               => '',
  };

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Animations — ${_vm.dieName}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProfile,
        tooltip: 'New profile',
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          if (_vm.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
              children: [
                if (_vm.statusMessage != null)
                  Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(_vm.statusMessage!)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _vm.clearStatus,
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // ── Built-in profiles ──────────────────────────────
                      SliverToBoxAdapter(
                        child: _CollapsibleSectionHeader(
                          title: 'Built-in Profiles',
                          expanded: _builtinsExpanded,
                          onTap: () => setState(() => _builtinsExpanded = !_builtinsExpanded),
                        ),
                      ),
                      if (_builtinsExpanded)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) {
                              final preset = kBuiltinProfiles[i];
                              final isTransferring = _vm.transferringId == preset.name;
                              final isOnDie = _vm.isBuiltinOnDie(preset);
                              final profile = preset.build();
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: ExpansionTile(
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Row(
                                      children: [
                                        Text(preset.name),
                                        if (isOnDie) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.check_circle, size: 14, color: Colors.green),
                                          const SizedBox(width: 2),
                                          Text('on die',
                                              style: TextStyle(fontSize: 11, color: Colors.green[700])),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      preset.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: isTransferring
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.upload),
                                            tooltip: 'Flash to die',
                                            onPressed: () => _vm.flashBuiltin.execute(preset),
                                          ),
                                    children: _ruleRows(profile, preset.name),
                                  ),
                                ),
                              );
                            },
                            childCount: kBuiltinProfiles.length,
                          ),
                        ),

                      // ── Custom profiles ────────────────────────────────
                      SliverToBoxAdapter(
                        child: _CollapsibleSectionHeader(
                          title: 'My Profiles',
                          expanded: _myProfilesExpanded,
                          onTap: () => setState(() => _myProfilesExpanded = !_myProfilesExpanded),
                        ),
                      ),
                      if (_myProfilesExpanded)
                        if (_vm.profiles.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  'No profiles yet.\nTap + to create one.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final p = _vm.profiles[i];
                                final isTransferring = _vm.transferringId == p.id;
                                final isOnDie = _vm.isProfileOnDie(p);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  child: Card(
                                    margin: EdgeInsets.zero,
                                    child: ExpansionTile(
                                      controlAffinity: ListTileControlAffinity.leading,
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
                                                    fontSize: 11, color: Colors.green[700])),
                                          ],
                                        ],
                                      ),
                                      trailing: isTransferring
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.upload),
                                                  tooltip: 'Flash to die',
                                                  onPressed: () => _vm.flashProfile.execute(p),
                                                ),
                                                PopupMenuButton<_Action>(
                                                  onSelected: (a) => switch (a) {
                                                    _Action.edit => _editProfile(p),
                                                    _Action.duplicate => _duplicateProfile(p),
                                                    _Action.delete => _deleteProfile(p),
                                                  },
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                                                    PopupMenuItem(value: _Action.duplicate, child: Text('Duplicate')),
                                                    PopupMenuItem(value: _Action.delete, child: Text('Delete')),
                                                  ],
                                                ),
                                              ],
                                            ),
                                      children: _ruleRows(p, p.id),
                                    ),
                                  ),
                                );
                              },
                              childCount: _vm.profiles.length,
                            ),
                          ),

                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
                ),
              ],
            );
        },
      ),
    );
  }
}

// ─── Collapsible section header ───────────────────────────────────────────────

class _CollapsibleSectionHeader extends StatelessWidget {
  const _CollapsibleSectionHeader({
    required this.title,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.labelLarge),
            ),
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

enum _Action { edit, duplicate, delete }

// ─── Preset picker (for creating a custom profile from a starting point) ──────

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
      'High Low'    => (Colors.green, Icons.trending_up),
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
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
