import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:roll_feathers/dice_sdks/pixels/pixels_animation.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_builtin_profiles.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels_patterns.dart';
import 'package:roll_feathers/domains/pixel_profile_domain.dart';
import 'package:roll_feathers/services/pixels/pixel_die_service.dart';
import 'package:roll_feathers/ui/pixels/pixels_profile_editor_screen_vm.dart';

/// Edits a single [PixelProfile]: name, list of animations, list of rules.
///
/// Returns the updated [PixelProfile] via [Navigator.pop] when saved,
/// or null when cancelled.
class PixelsProfileEditorScreen extends StatefulWidget {
  const PixelsProfileEditorScreen({super.key, required this.viewModel});

  /// Builds the editor with a [PixelsProfileEditorViewModel] for [profile].
  static PixelsProfileEditorScreen create(
    PixelProfileDomain domain,
    PixelDieService? dieService,
    PixelProfile profile,
  ) =>
      PixelsProfileEditorScreen(
        viewModel: PixelsProfileEditorViewModel(domain, dieService, profile),
      );

  final PixelsProfileEditorViewModel viewModel;

  @override
  State<PixelsProfileEditorScreen> createState() => _PixelsProfileEditorScreenState();
}

class _PixelsProfileEditorScreenState extends State<PixelsProfileEditorScreen> {
  PixelsProfileEditorViewModel get _vm => widget.viewModel;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _vm.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_vm.buildProfile(_nameCtrl.text));

  /// Runs a preview command, then surfaces the VM's resulting status (the
  /// success/failure text Commands don't model) as a SnackBar.
  Future<void> _runPreview(Future<void> Function() exec) async {
    await exec();
    if (!mounted) return;
    final msg = _vm.statusMessage;
    if (msg != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
    }
  }

  // ── Animations ────────────────────────────────────────────────────────────

  Future<void> _addAnimation() async {
    final result = await _showAnimationEditor(null);
    if (result != null) _vm.addAnimation(result);
  }

  /// Imports an animation from a built-in profile as a starting point.
  ///
  /// Animations are deep-cloned (via JSON round-trip) so edits never touch the
  /// source built-in. If the chosen animation references siblings — a
  /// [PixelAnimationSequence] points at other animations by index — those are
  /// pulled in too (transitively) and the Sequence's indices are remapped to
  /// the clones' new positions, so the import doesn't dangle.
  Future<void> _importAnimation() async {
    final chosen = await showModalBottomSheet<_ImportSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ImportAnimationSheet(profiles: _vm.builtins),
    );
    if (chosen == null || !mounted) return;
    final count = _vm.importAnimation(chosen.source, chosen.index);
    if (count > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported with ${count - 1} referenced animation${count - 1 == 1 ? '' : 's'}')),
      );
    }
  }

  Future<void> _editAnimation(int index) async {
    final result = await _showAnimationEditor(_vm.animations[index], editIndex: index);
    if (result != null) _vm.replaceAnimation(index, result);
  }

  Future<PixelAnimation?> _showAnimationEditor(PixelAnimation? existing, {int? editIndex}) {
    return showDialog<PixelAnimation>(
      context: context,
      builder: (_) => _AnimationEditorDialog(
        animation: existing,
        animCount: _vm.animations.length,
        onPreview: _vm.canPreview ? (anim) => _runPreview(() => _vm.previewInContext(anim, replaceIndex: editIndex)) : null,
      ),
    );
  }

  // ── Rules ─────────────────────────────────────────────────────────────────

  Future<void> _addRule() async {
    if (_vm.animations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one animation first')),
      );
      return;
    }
    final result = await _showRuleEditor(null);
    if (result != null) _vm.addRule(result);
  }

  Future<void> _editRule(int index) async {
    final result = await _showRuleEditor(_vm.rules[index]);
    if (result != null) _vm.replaceRule(index, result);
  }

  Future<PixelRule?> _showRuleEditor(PixelRule? existing) {
    return showDialog<PixelRule>(
      context: context,
      builder: (_) => _RuleEditorDialog(
        rule: existing,
        animationCount: _vm.animations.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile name
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Profile Name'),
            ),
            const SizedBox(height: 24),

            // Animations section
            Row(
              children: [
                const Expanded(child: Text('Animations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                TextButton.icon(
                  onPressed: _importAnimation,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Import'),
                ),
                TextButton.icon(
                  onPressed: _addAnimation,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_vm.animations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No animations yet.', style: TextStyle(color: Colors.grey)),
              ),
            ...List.generate(_vm.animations.length, (i) {
              final anim = _vm.animations[i];
              return Card(
                child: ListTile(
                  leading: _AnimationIcon(anim),
                  title: Text(_animLabel(i, anim)),
                  subtitle: Text(_animSubtitle(anim)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_vm.canPreview)
                        IconButton(
                          icon: const Icon(Icons.play_circle_outline, size: 20),
                          tooltip: 'Preview on die',
                          onPressed: _vm.preview.running ? null : () => _runPreview(() => _vm.preview.execute(_vm.animations, i)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editAnimation(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _vm.deleteAnimation(i),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Rules section
            Row(
              children: [
                const Expanded(child: Text('Rules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                TextButton.icon(
                  onPressed: _addRule,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_vm.rules.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No rules yet.', style: TextStyle(color: Colors.grey)),
              ),
            ...List.generate(_vm.rules.length, (i) {
              final rule = _vm.rules[i];
              return Card(
                child: ListTile(
                  title: Text('When: ${rule.condition.displayName}'),
                  subtitle: Text(_ruleSubtitle(rule)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editRule(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _vm.deleteRule(i),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _animLabel(int i, PixelAnimation anim) => 'Animation ${i + 1}: ${_animTypeName(anim)}';

  String _ruleSubtitle(PixelRule rule) {
    final actions = rule.actions.map((a) {
      if (a is PixelActionPlayAnimation) return 'Play animation ${a.animIndex + 1}';
      return 'Action';
    }).join(', ');
    return 'Then: $actions';
  }
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
  PixelAnimationSimple s   => '${s.durationMs}ms · rgb(${s.color.r},${s.color.g},${s.color.b}) · ×${s.count}',
  PixelAnimationRainbow r  => '${r.durationMs}ms · intensity ${r.intensity}',
  PixelAnimationGradient g => '${g.durationMs}ms · flow',
  PixelAnimationCycle c    => '${c.durationMs}ms · intensity ${c.intensity}',
  PixelAnimationNoise n    => '${n.durationMs}ms · noise',
  PixelAnimationNormals n  => '${n.durationMs}ms · directional',
  PixelAnimationSequence s        => '${s.entries.length} part${s.entries.length == 1 ? '' : 's'}',
  PixelAnimationKeyframed k       => '${k.durationMs}ms · ${k.pattern?.name ?? 'no pattern'}',
  PixelAnimationGradientPattern g => '${g.durationMs}ms · ${g.pattern?.name ?? 'no pattern'}',
  _                               => '',
};

/// Bottom sheet listing every built-in profile's animations; tapping one pops
/// it back to the caller to be imported as a base for a custom animation.
class _ImportAnimationSheet extends StatelessWidget {
  const _ImportAnimationSheet({required this.profiles});
  final List<BuiltinProfile> profiles;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Import an animation', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final preset in profiles)
                  _ImportProfileTile(preset: preset),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportProfileTile extends StatelessWidget {
  const _ImportProfileTile({required this.preset});
  final BuiltinProfile preset;

  @override
  Widget build(BuildContext context) {
    final anims = preset.build().animations;
    return ExpansionTile(
      title: Text(preset.name),
      subtitle: Text('${anims.length} animation${anims.length == 1 ? '' : 's'}'),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: [
        for (var i = 0; i < anims.length; i++)
          ListTile(
            dense: true,
            leading: _AnimationIcon(anims[i]),
            title: Text(_animTypeName(anims[i])),
            subtitle: Text(_animSubtitle(anims[i])),
            // Pop the whole source set + index so the importer can pull in any
            // animations this one references (e.g. a Sequence's sub-animations).
            onTap: () => Navigator.pop<_ImportSelection>(context, (source: anims, index: i)),
          ),
      ],
    );
  }
}

/// A chosen animation to import: its index within the source profile's full
/// animation [source] list, so sibling references can be resolved.
typedef _ImportSelection = ({List<PixelAnimation> source, int index});

class _AnimationIcon extends StatelessWidget {
  const _AnimationIcon(this.anim);
  final PixelAnimation anim;

  @override
  Widget build(BuildContext context) {
    if (anim is PixelAnimationSimple) {
      final c = (anim as PixelAnimationSimple).color;
      return CircleAvatar(backgroundColor: Color.fromARGB(255, c.r, c.g, c.b));
    }
    final (icon, color) = switch (anim) {
      PixelAnimationRainbow _         => (Icons.auto_awesome, Colors.purple),
      PixelAnimationGradient _        => (Icons.water, Colors.blue),
      PixelAnimationCycle _           => (Icons.loop, Colors.teal),
      PixelAnimationNoise _           => (Icons.grain, Colors.blueGrey),
      PixelAnimationNormals _         => (Icons.layers, Colors.indigo),
      PixelAnimationSequence _        => (Icons.playlist_play, Colors.orange),
      PixelAnimationKeyframed _       => (Icons.timeline, Colors.deepPurple),
      PixelAnimationGradientPattern _ => (Icons.gradient, Colors.cyan),
      _                               => (Icons.timeline, Colors.grey),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, color: color, size: 16),
    );
  }
}

// ─── Gradient state ───────────────────────────────────────────────────────────

enum _GradPreset { rainbow, fire, water, solid, twoColor, custom }

class _GradState {
  _GradPreset preset;
  int r1, g1, b1;
  int r2, g2, b2;

  /// For [_GradPreset.custom]: the source gradient, kept verbatim so a bespoke
  /// gradient the editor can't author (e.g. the purple Magic cycle gradient)
  /// survives an edit instead of being snapped to a preset.
  final PixelGradient? original;

  _GradState({
    this.preset = _GradPreset.rainbow,
    this.r1 = 255, this.g1 = 0, this.b1 = 0,
    this.r2 = 0,   this.g2 = 0, this.b2 = 255,
    this.original,
  });

  PixelGradient build() => switch (preset) {
    _GradPreset.rainbow  => PixelGradient.rainbow,
    _GradPreset.fire     => PixelGradient.fire,
    _GradPreset.water    => PixelGradient.water,
    _GradPreset.solid    => PixelGradient.solid(PixelColor(r1, g1, b1)),
    _GradPreset.twoColor => PixelGradient.twoColor(PixelColor(r1, g1, b1), PixelColor(r2, g2, b2)),
    _GradPreset.custom   => original ?? PixelGradient.rainbow,
  };

  static bool _matches(PixelGradient a, PixelGradient b) {
    if (a.keyframes.length != b.keyframes.length) return false;
    for (var i = 0; i < a.keyframes.length; i++) {
      if (a.keyframes[i] != b.keyframes[i]) return false;
    }
    return true;
  }

  static _GradState fromGradient(PixelGradient g) {
    // Exact matches against the authorable presets first.
    if (_matches(g, PixelGradient.rainbow)) return _GradState(preset: _GradPreset.rainbow);
    if (_matches(g, PixelGradient.fire))    return _GradState(preset: _GradPreset.fire);
    if (_matches(g, PixelGradient.water))   return _GradState(preset: _GradPreset.water);
    final kfs = g.keyframes;
    if (kfs.length == 2) {
      final c = kfs[0].$2;
      return _GradState(preset: _GradPreset.solid, r1: c.r, g1: c.g, b1: c.b);
    }
    if (kfs.length == 3) {
      final c1 = kfs[0].$2, c2 = kfs[1].$2;
      return _GradState(preset: _GradPreset.twoColor, r1: c1.r, g1: c1.g, b1: c1.b, r2: c2.r, g2: c2.g, b2: c2.b);
    }
    // Unrecognized — preserve it verbatim rather than snapping to a preset.
    return _GradState(preset: _GradPreset.custom, original: g);
  }
}

// ─── Animation editor dialog ──────────────────────────────────────────────────

enum _AnimType { solid, rainbow, blinkId, gradient, cycle, noise, normals, sequence, keyframed, gradientPattern }

class _AnimationEditorDialog extends StatefulWidget {
  const _AnimationEditorDialog({this.animation, required this.animCount, this.onPreview});
  final PixelAnimation? animation;
  final int animCount;

  /// Plays the in-progress animation on the die. Null when no die is connected.
  final Future<void> Function(PixelAnimation)? onPreview;

  @override
  State<_AnimationEditorDialog> createState() => _AnimationEditorDialogState();
}

class _AnimationEditorDialogState extends State<_AnimationEditorDialog> {
  late _AnimType _type;

  // ── Solid Flash
  int _r = 255, _g = 0, _b = 0;
  int _durationMs = 500;
  int _count = 1;
  int _fade = 128;

  // ── Rainbow
  int _rainbowDuration = 2000;
  int _intensity = 200;

  // ── Blink ID
  int _blinkIdDuration = 1000;
  int _framesPerBlink = 6;

  // ── Gradient / Flow
  int _gradFlowDuration = 1000;
  _GradState _gradFlowGrad = _GradState();

  // ── Color Cycle
  int _cycleDuration = 2000;
  int _cycleCount = 1;
  int _cycleFade = 0;
  int _cycleIntensity = 128;
  int _cyclesTimes10 = 10;
  _GradState _cycleGrad = _GradState();

  // ── Noise
  int _noiseDuration = 3000;
  int _noiseFade = 128;
  _GradState _noiseGrad = _GradState();
  _GradState _noiseBlinkGrad = _GradState(preset: _GradPreset.solid, r1: 255, g1: 255, b1: 255);
  int _blinkFreqTimes1000 = 1000;
  int _blinkDuration = 100;

  // ── Normals
  int _normDuration = 3000;
  int _normFade = 0;
  _GradState _normGrad = _GradState();
  int _axisScrollTimes1000 = 1000;
  int _angleScrollTimes1000 = 0;
  int _axisScaleTimes1000 = 1000;

  // ── Sequence
  List<(int, int)> _seqEntries = [];

  // ── Keyframed
  PixelPattern? _keyframedPattern;
  int _keyframedDuration = 1000;

  // ── Gradient Pattern
  PixelPattern? _gpPattern;
  int _gpDuration = 2000;
  _GradState _gpGrad = _GradState();

  @override
  void initState() {
    super.initState();
    final a = widget.animation;
    if (a is PixelAnimationRainbow) {
      _type = _AnimType.rainbow;
      _rainbowDuration = a.durationMs;
      _intensity = a.intensity;
    } else if (a is PixelAnimationBlinkId) {
      _type = _AnimType.blinkId;
      _blinkIdDuration = a.durationMs;
      _framesPerBlink = a.framesPerBlink;
    } else if (a is PixelAnimationGradient) {
      _type = _AnimType.gradient;
      _gradFlowDuration = a.durationMs;
      _gradFlowGrad = _GradState.fromGradient(a.gradient);
    } else if (a is PixelAnimationCycle) {
      _type = _AnimType.cycle;
      _cycleDuration = a.durationMs;
      _cycleCount = a.count;
      _cycleFade = a.fade;
      _cycleIntensity = a.intensity;
      _cyclesTimes10 = a.cyclesTimes10;
      _cycleGrad = _GradState.fromGradient(a.gradient);
    } else if (a is PixelAnimationNoise) {
      _type = _AnimType.noise;
      _noiseDuration = a.durationMs;
      _noiseFade = a.fade;
      _noiseGrad = _GradState.fromGradient(a.gradient);
      _noiseBlinkGrad = _GradState.fromGradient(a.blinkGradient);
      _blinkFreqTimes1000 = a.blinkFrequencyTimes1000;
      _blinkDuration = a.blinkDuration;
    } else if (a is PixelAnimationNormals) {
      _type = _AnimType.normals;
      _normDuration = a.durationMs;
      _normFade = a.fade;
      _normGrad = _GradState.fromGradient(a.gradient);
      _axisScrollTimes1000 = a.axisScrollSpeedTimes1000;
      _angleScrollTimes1000 = a.angleScrollSpeedTimes1000;
      _axisScaleTimes1000 = a.axisScaleTimes1000;
    } else if (a is PixelAnimationSequence) {
      _type = _AnimType.sequence;
      _seqEntries = List.of(a.entries);
    } else if (a is PixelAnimationKeyframed) {
      _type = _AnimType.keyframed;
      _keyframedDuration = a.durationMs;
      _keyframedPattern = a.pattern;
    } else if (a is PixelAnimationGradientPattern) {
      _type = _AnimType.gradientPattern;
      _gpDuration = a.durationMs;
      _gpPattern = a.pattern;
      _gpGrad = _GradState.fromGradient(a.gradient);
    } else {
      _type = _AnimType.solid;
      if (a is PixelAnimationSimple) {
        _r = a.color.r; _g = a.color.g; _b = a.color.b;
        _durationMs = a.durationMs;
        _count = a.count;
        _fade = a.fade;
      }
    }
  }

  PixelAnimation _build() {
    final anim = _buildTyped();
    _preserveHiddenFields(anim);
    return anim;
  }

  /// Copies fields the dialog doesn't expose (animFlags, faceMask) from the
  /// original animation when the type is unchanged, so editing one exposed
  /// parameter doesn't silently reset the rest (e.g. the Magic cycle's
  /// `animFlags: 2`). When the user switches Type, hidden fields reset to the
  /// new type's defaults, which is correct.
  void _preserveHiddenFields(PixelAnimation anim) {
    final orig = widget.animation;
    if (orig == null || orig.runtimeType != anim.runtimeType) return;
    switch (anim) {
      case PixelAnimationSimple a when orig is PixelAnimationSimple:
        a.animFlags = orig.animFlags;
        a.faceMask = orig.faceMask;
      case PixelAnimationRainbow a when orig is PixelAnimationRainbow:
        a.animFlags = orig.animFlags;
        a.faceMask = orig.faceMask;
      case PixelAnimationGradient a when orig is PixelAnimationGradient:
        a.animFlags = orig.animFlags;
        a.faceMask = orig.faceMask;
      case PixelAnimationCycle a when orig is PixelAnimationCycle:
        a.animFlags = orig.animFlags;
        a.faceMask = orig.faceMask;
      case PixelAnimationBlinkId a when orig is PixelAnimationBlinkId:
        a.animFlags = orig.animFlags;
      case PixelAnimationNoise a when orig is PixelAnimationNoise:
        a.animFlags = orig.animFlags;
      case PixelAnimationNormals a when orig is PixelAnimationNormals:
        a.animFlags = orig.animFlags;
      case PixelAnimationGradientPattern a when orig is PixelAnimationGradientPattern:
        a.animFlags = orig.animFlags;
      case PixelAnimationSequence a when orig is PixelAnimationSequence:
        a.animFlags = orig.animFlags;
      case PixelAnimationKeyframed a when orig is PixelAnimationKeyframed:
        a.animFlags = orig.animFlags;
    }
  }

  PixelAnimation _buildTyped() {
    return switch (_type) {
      _AnimType.solid => PixelAnimationSimple(
          durationMs: _durationMs,
          color: PixelColor(_r, _g, _b),
          count: _count,
          fade: _fade,
        ),
      _AnimType.rainbow => PixelAnimationRainbow(
          durationMs: _rainbowDuration,
          intensity: _intensity,
        ),
      _AnimType.blinkId => PixelAnimationBlinkId(
          durationMs: _blinkIdDuration,
          framesPerBlink: _framesPerBlink,
        ),
      _AnimType.gradient => PixelAnimationGradient(
          durationMs: _gradFlowDuration,
          gradient: _gradFlowGrad.build(),
        ),
      _AnimType.cycle => PixelAnimationCycle(
          durationMs: _cycleDuration,
          count: _cycleCount,
          fade: _cycleFade,
          intensity: _cycleIntensity,
          cyclesTimes10: _cyclesTimes10,
          gradient: _cycleGrad.build(),
        ),
      _AnimType.noise => PixelAnimationNoise(
          durationMs: _noiseDuration,
          fade: _noiseFade,
          gradient: _noiseGrad.build(),
          blinkGradient: _noiseBlinkGrad.build(),
          blinkFrequencyTimes1000: _blinkFreqTimes1000,
          blinkFrequencyVarTimes1000: (_blinkFreqTimes1000 * 0.5).round(),
          blinkDuration: _blinkDuration,
        ),
      _AnimType.normals => PixelAnimationNormals(
          durationMs: _normDuration,
          fade: _normFade,
          gradient: _normGrad.build(),
          axisScaleTimes1000: _axisScaleTimes1000,
          axisScrollSpeedTimes1000: _axisScrollTimes1000,
          angleScrollSpeedTimes1000: _angleScrollTimes1000,
        ),
      _AnimType.sequence => PixelAnimationSequence(
          entries: List.of(_seqEntries),
        ),
      _AnimType.keyframed => PixelAnimationKeyframed(
          durationMs: _keyframedDuration,
          pattern: _keyframedPattern,
        ),
      _AnimType.gradientPattern => PixelAnimationGradientPattern(
          durationMs: _gpDuration,
          pattern: _gpPattern,
          gradient: _gpGrad.build(),
        ),
    };
  }

  // ── Gradient section helper ────────────────────────────────────────────────

  List<Widget> _gradSection(String label, _GradState s) {
    return [
      DropdownButtonFormField<_GradPreset>(
        value: s.preset,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: _GradPreset.rainbow,  child: Text('Rainbow')),
          const DropdownMenuItem(value: _GradPreset.fire,     child: Text('Fire')),
          const DropdownMenuItem(value: _GradPreset.water,    child: Text('Water')),
          const DropdownMenuItem(value: _GradPreset.solid,    child: Text('Solid Color')),
          const DropdownMenuItem(value: _GradPreset.twoColor, child: Text('Two Color')),
          // Only selectable when the source gradient isn't an authorable preset;
          // picking another option replaces it (a custom gradient editor is TODO).
          if (s.preset == _GradPreset.custom)
            const DropdownMenuItem(value: _GradPreset.custom, child: Text('Custom (from source)')),
        ],
        onChanged: (v) { if (v != null) setState(() => s.preset = v); },
      ),
      if (s.preset == _GradPreset.custom)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Keeping the original gradient. Choosing a preset above replaces it.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      if (s.preset == _GradPreset.solid || s.preset == _GradPreset.twoColor) ...[
        const SizedBox(height: 8),
        if (s.preset == _GradPreset.twoColor)
          const Text('Start color', style: TextStyle(fontSize: 12, color: Colors.grey)),
        Row(
          children: [
            Expanded(child: _intField('R', s.r1, 0, 255, (v) => s.r1 = v)),
            const SizedBox(width: 6),
            Expanded(child: _intField('G', s.g1, 0, 255, (v) => s.g1 = v)),
            const SizedBox(width: 6),
            Expanded(child: _intField('B', s.b1, 0, 255, (v) => s.b1 = v)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 24,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, s.r1, s.g1, s.b1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
      ],
      if (s.preset == _GradPreset.twoColor) ...[
        const SizedBox(height: 8),
        const Text('End color', style: TextStyle(fontSize: 12, color: Colors.grey)),
        Row(
          children: [
            Expanded(child: _intField('R', s.r2, 0, 255, (v) => s.r2 = v)),
            const SizedBox(width: 6),
            Expanded(child: _intField('G', s.g2, 0, 255, (v) => s.g2 = v)),
            const SizedBox(width: 6),
            Expanded(child: _intField('B', s.b2, 0, 255, (v) => s.b2 = v)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 24,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, s.r2, s.g2, s.b2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
      ],
    ];
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final availableTypes = _AnimType.values.where((t) {
      if (t == _AnimType.sequence && widget.animCount == 0) return false;
      return true;
    }).toList();

    return AlertDialog(
      title: const Text('Edit Animation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Type selector ──────────────────────────────────────────────
            DropdownButtonFormField<_AnimType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: availableTypes.map((t) => DropdownMenuItem(
                value: t,
                child: Text(switch (t) {
                  _AnimType.solid           => 'Solid Flash',
                  _AnimType.rainbow         => 'Rainbow',
                  _AnimType.blinkId         => 'Blink ID',
                  _AnimType.gradient        => 'Flow',
                  _AnimType.cycle           => 'Color Cycle',
                  _AnimType.noise           => 'Noise',
                  _AnimType.normals         => 'Normals',
                  _AnimType.sequence        => 'Sequence',
                  _AnimType.keyframed       => 'Keyframed',
                  _AnimType.gradientPattern => 'Gradient Pattern',
                }),
              )).toList(),
              onChanged: (v) { if (v != null) setState(() => _type = v); },
            ),
            const SizedBox(height: 16),

            // ── Solid Flash ────────────────────────────────────────────────
            if (_type == _AnimType.solid) ...[
              _intField('Duration (ms)', _durationMs, 100, 10000, (v) => _durationMs = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _intField('R', _r, 0, 255, (v) => _r = v)),
                  const SizedBox(width: 8),
                  Expanded(child: _intField('G', _g, 0, 255, (v) => _g = v)),
                  const SizedBox(width: 8),
                  Expanded(child: _intField('B', _b, 0, 255, (v) => _b = v)),
                ],
              ),
              const SizedBox(height: 8),
              _intField('Count (loops)', _count, 1, 255, (v) => _count = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Fade'),
                  Expanded(
                    child: Slider(
                      value: _fade.toDouble(),
                      min: 0, max: 255,
                      onChanged: (v) => setState(() => _fade = v.round()),
                    ),
                  ),
                  Text('$_fade'),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, _r, _g, _b),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                ),
              ),
            ],

            // ── Rainbow ────────────────────────────────────────────────────
            if (_type == _AnimType.rainbow) ...[
              _intField('Duration (ms)', _rainbowDuration, 100, 10000, (v) => _rainbowDuration = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Intensity'),
                  Expanded(
                    child: Slider(
                      value: _intensity.toDouble(),
                      min: 0, max: 255,
                      onChanged: (v) => setState(() => _intensity = v.round()),
                    ),
                  ),
                  Text('$_intensity'),
                ],
              ),
            ],

            // ── Blink ID ───────────────────────────────────────────────────
            if (_type == _AnimType.blinkId) ...[
              _intField('Preamble duration (ms)', _blinkIdDuration, 100, 10000, (v) => _blinkIdDuration = v),
              const SizedBox(height: 8),
              _intField('Frames per blink', _framesPerBlink, 1, 30, (v) => _framesPerBlink = v),
              const SizedBox(height: 8),
              const Text(
                'Blinks the die\'s identity (white preamble, then an ID pattern on all LEDs).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],

            // ── Flow (Gradient) ────────────────────────────────────────────
            if (_type == _AnimType.gradient) ...[
              _intField('Duration (ms)', _gradFlowDuration, 100, 10000, (v) => _gradFlowDuration = v),
              const SizedBox(height: 8),
              ..._gradSection('Gradient', _gradFlowGrad),
            ],

            // ── Color Cycle ────────────────────────────────────────────────
            if (_type == _AnimType.cycle) ...[
              _intField('Duration (ms)', _cycleDuration, 100, 10000, (v) => _cycleDuration = v),
              const SizedBox(height: 8),
              _intField('Count (loops)', _cycleCount, 1, 10, (v) => _cycleCount = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Intensity'),
                  Expanded(
                    child: Slider(
                      value: _cycleIntensity.toDouble(),
                      min: 0, max: 255,
                      onChanged: (v) => setState(() => _cycleIntensity = v.round()),
                    ),
                  ),
                  Text('$_cycleIntensity'),
                ],
              ),
              Row(
                children: [
                  const Text('Speed'),
                  Expanded(
                    child: Slider(
                      value: _cyclesTimes10.toDouble(),
                      min: 1, max: 50,
                      onChanged: (v) => setState(() => _cyclesTimes10 = v.round()),
                    ),
                  ),
                  Text('${(_cyclesTimes10 / 10).toStringAsFixed(1)}×'),
                ],
              ),
              Row(
                children: [
                  const Text('Fade'),
                  Expanded(
                    child: Slider(
                      value: _cycleFade.toDouble(),
                      min: 0, max: 255,
                      onChanged: (v) => setState(() => _cycleFade = v.round()),
                    ),
                  ),
                  Text('$_cycleFade'),
                ],
              ),
              const SizedBox(height: 4),
              ..._gradSection('Gradient', _cycleGrad),
            ],

            // ── Noise ──────────────────────────────────────────────────────
            if (_type == _AnimType.noise) ...[
              _intField('Duration (ms)', _noiseDuration, 100, 10000, (v) => _noiseDuration = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Fade'),
                  Expanded(
                    child: Slider(
                      value: _noiseFade.toDouble(),
                      min: 0, max: 255,
                      onChanged: (v) => setState(() => _noiseFade = v.round()),
                    ),
                  ),
                  Text('$_noiseFade'),
                ],
              ),
              const SizedBox(height: 4),
              ..._gradSection('Background Gradient', _noiseGrad),
              const SizedBox(height: 8),
              ..._gradSection('Spark Color', _noiseBlinkGrad),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Spark Rate'),
                  Expanded(
                    child: Slider(
                      value: _blinkFreqTimes1000.toDouble(),
                      min: 200, max: 5000,
                      onChanged: (v) => setState(() => _blinkFreqTimes1000 = v.round()),
                    ),
                  ),
                  Text('${(_blinkFreqTimes1000 / 1000).toStringAsFixed(1)} Hz'),
                ],
              ),
              _intField('Spark Duration (ms)', _blinkDuration, 20, 500, (v) => _blinkDuration = v),
            ],

            // ── Normals ────────────────────────────────────────────────────
            if (_type == _AnimType.normals) ...[
              _intField('Duration (ms)', _normDuration, 100, 10000, (v) => _normDuration = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Fade'),
                  Expanded(
                    child: Slider(
                      value: _normFade.toDouble(),
                      min: 0, max: 255,
                      onChanged: (v) => setState(() => _normFade = v.round()),
                    ),
                  ),
                  Text('$_normFade'),
                ],
              ),
              const SizedBox(height: 4),
              ..._gradSection('Gradient', _normGrad),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Axis Scale', style: TextStyle(fontSize: 13))),
                  Text((_axisScaleTimes1000 / 1000).toStringAsFixed(2)),
                ],
              ),
              Slider(
                value: _axisScaleTimes1000.toDouble(),
                min: 100, max: 3000,
                onChanged: (v) => setState(() => _axisScaleTimes1000 = v.round()),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Axis Scroll (waterfall)', style: TextStyle(fontSize: 13))),
                  Text((_axisScrollTimes1000 / 1000).toStringAsFixed(2)),
                ],
              ),
              Slider(
                value: _axisScrollTimes1000.toDouble(),
                min: -3000, max: 3000,
                onChanged: (v) => setState(() => _axisScrollTimes1000 = v.round()),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Angle Scroll (spiral)', style: TextStyle(fontSize: 13))),
                  Text((_angleScrollTimes1000 / 1000).toStringAsFixed(2)),
                ],
              ),
              Slider(
                value: _angleScrollTimes1000.toDouble(),
                min: -3000, max: 3000,
                onChanged: (v) => setState(() => _angleScrollTimes1000 = v.round()),
              ),
            ],

            // ── Keyframed ──────────────────────────────────────────────────
            if (_type == _AnimType.keyframed) ...[
              _intField('Duration (ms)', _keyframedDuration, 100, 10000, (v) => _keyframedDuration = v),
              const SizedBox(height: 8),
              DropdownButtonFormField<PixelPattern?>(
                value: _keyframedPattern,
                decoration: const InputDecoration(labelText: 'Pattern'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— none —')),
                  ...kBuiltinPatterns.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
                ],
                onChanged: (v) => setState(() => _keyframedPattern = v),
              ),
            ],

            // ── Gradient Pattern ───────────────────────────────────────────
            if (_type == _AnimType.gradientPattern) ...[
              _intField('Duration (ms)', _gpDuration, 100, 10000, (v) => _gpDuration = v),
              const SizedBox(height: 8),
              DropdownButtonFormField<PixelPattern?>(
                value: _gpPattern,
                decoration: const InputDecoration(labelText: 'Pattern'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— none —')),
                  ...kBuiltinPatterns.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
                ],
                onChanged: (v) => setState(() => _gpPattern = v),
              ),
              const SizedBox(height: 8),
              ..._gradSection('Color Gradient', _gpGrad),
            ],

            // ── Sequence ───────────────────────────────────────────────────
            if (_type == _AnimType.sequence) ...[
              const Text(
                'Plays up to 4 animations in sequence.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ..._seqEntries.asMap().entries.map((e) {
                final idx = e.key;
                final (animIdx, delayMs) = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text('${idx + 1}.', style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: animIdx.clamp(0, widget.animCount - 1),
                          decoration: const InputDecoration(
                            labelText: 'Animation',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                          items: List.generate(widget.animCount, (i) => DropdownMenuItem(
                            value: i,
                            child: Text('Anim ${i + 1}'),
                          )),
                          onChanged: (v) {
                            if (v != null) setState(() => _seqEntries[idx] = (v, delayMs));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: TextEditingController(text: '$delayMs'),
                          decoration: const InputDecoration(
                            labelText: 'Delay ms',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (s) {
                            final v = int.tryParse(s) ?? 0;
                            setState(() => _seqEntries[idx] = (animIdx, v.clamp(0, 5000)));
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        onPressed: () => setState(() => _seqEntries.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
              if (_seqEntries.length < 4)
                TextButton.icon(
                  onPressed: () => setState(() => _seqEntries.add((0, 0))),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add step'),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.onPreview != null)
          TextButton.icon(
            onPressed: _previewBusy
                ? null
                : () async {
                    setState(() => _previewBusy = true);
                    try {
                      await widget.onPreview!(_build());
                    } finally {
                      if (mounted) setState(() => _previewBusy = false);
                    }
                  },
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Preview'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _build()), child: const Text('OK')),
      ],
    );
  }

  bool _previewBusy = false;

  Widget _intField(String label, int initial, int min, int max, void Function(int) onChanged) {
    final ctrl = TextEditingController(text: '$initial');
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (s) {
        final v = int.tryParse(s) ?? initial;
        setState(() => onChanged(v.clamp(min, max)));
      },
    );
  }
}

// ─── Rule editor dialog ───────────────────────────────────────────────────────

enum _CondType { rolled, rolling, helloGoodbye, handling, crooked, idle, battery, connection }

class _RuleEditorDialog extends StatefulWidget {
  const _RuleEditorDialog({this.rule, required this.animationCount});
  final PixelRule? rule;
  final int animationCount;

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late _CondType _condType;
  int _faceMask = 0xFFFFF; // all 20 faces
  int _rollingPeriodMs = 300;
  int _helloFlags = PixelHelloFlags.both;
  int _battFlags = PixelBatteryFlags.low;
  int _battPeriodMs = 5000;
  int _connFlags = PixelConnectionFlags.both;
  int _idlePeriodMs = 0;

  int _animIndex = 0;
  int _loopCount = 1;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    if (rule == null) {
      _condType = _CondType.rolled;
    } else {
      final c = rule.condition;
      if (c is PixelConditionRolled) {
        _condType = _CondType.rolled;
        _faceMask = c.faceMask;
      } else if (c is PixelConditionRolling) {
        _condType = _CondType.rolling;
        _rollingPeriodMs = c.repeatPeriodMs;
      } else if (c is PixelConditionHelloGoodbye) {
        _condType = _CondType.helloGoodbye;
        _helloFlags = c.flags;
      } else if (c is PixelConditionCrooked) {
        _condType = _CondType.crooked;
      } else if (c is PixelConditionIdle) {
        _condType = _CondType.idle;
        _idlePeriodMs = c.repeatPeriodMs;
      } else if (c is PixelConditionBatteryState) {
        _condType = _CondType.battery;
        _battFlags = c.flags;
        _battPeriodMs = c.repeatPeriodMs;
      } else if (c is PixelConditionConnectionState) {
        _condType = _CondType.connection;
        _connFlags = c.flags;
      } else {
        _condType = _CondType.handling;
      }
      final action = rule.actions.whereType<PixelActionPlayAnimation>().firstOrNull;
      if (action != null) {
        // Guard the clamp: animationCount-1 == -1 when the profile has no
        // animations (all deleted), which would make clamp(0, -1) throw.
        _animIndex = widget.animationCount > 0
            ? action.animIndex.clamp(0, widget.animationCount - 1)
            : 0;
        _loopCount = action.loopCount;
      }
    }
  }

  PixelRule _build() {
    final PixelCondition cond = switch (_condType) {
      _CondType.rolled       => PixelConditionRolled(faceMask: _faceMask),
      _CondType.rolling      => PixelConditionRolling(repeatPeriodMs: _rollingPeriodMs),
      _CondType.helloGoodbye => PixelConditionHelloGoodbye(flags: _helloFlags),
      _CondType.handling     => PixelConditionHandling(),
      _CondType.crooked      => PixelConditionCrooked(),
      _CondType.idle         => PixelConditionIdle(repeatPeriodMs: _idlePeriodMs),
      _CondType.battery      => PixelConditionBatteryState(flags: _battFlags, repeatPeriodMs: _battPeriodMs),
      _CondType.connection   => PixelConditionConnectionState(flags: _connFlags),
    };
    return PixelRule(
      condition: cond,
      actions: [PixelActionPlayAnimation(animIndex: _animIndex, loopCount: _loopCount)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Rule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Condition', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<_CondType>(
              value: _condType,
              items: const [
                DropdownMenuItem(value: _CondType.rolled,       child: Text('Rolled (face landed)')),
                DropdownMenuItem(value: _CondType.rolling,      child: Text('Rolling (in motion)')),
                DropdownMenuItem(value: _CondType.helloGoodbye, child: Text('Hello / Goodbye')),
                DropdownMenuItem(value: _CondType.handling,     child: Text('Handling (picked up)')),
                DropdownMenuItem(value: _CondType.crooked,      child: Text('Crooked (landed askew)')),
                DropdownMenuItem(value: _CondType.idle,         child: Text('Idle (resting)')),
                DropdownMenuItem(value: _CondType.battery,      child: Text('Battery state')),
                DropdownMenuItem(value: _CondType.connection,   child: Text('Connection (BLE)')),
              ],
              onChanged: (v) { if (v != null) setState(() => _condType = v); },
            ),
            const SizedBox(height: 8),
            if (_condType == _CondType.rolled) ...[
              const Text('Face Mask (hex)'),
              const SizedBox(height: 4),
              TextFormField(
                initialValue: _faceMask.toRadixString(16).toUpperCase(),
                decoration: const InputDecoration(hintText: 'FFFFF = all faces'),
                onChanged: (s) {
                  final v = int.tryParse(s, radix: 16);
                  if (v != null) setState(() => _faceMask = v);
                },
              ),
              const SizedBox(height: 4),
              _FaceMaskChips(
                mask: _faceMask,
                faces: 20,
                onChanged: (m) => setState(() => _faceMask = m),
              ),
            ],
            if (_condType == _CondType.rolling) ...[
              const SizedBox(height: 8),
              Text('Repeat period: $_rollingPeriodMs ms'),
              Slider(
                value: _rollingPeriodMs.toDouble(),
                min: 100, max: 2000,
                divisions: 19,
                onChanged: (v) => setState(() => _rollingPeriodMs = v.round()),
              ),
            ],
            if (_condType == _CondType.helloGoodbye) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('On Hello (wake up)'),
                value: (_helloFlags & PixelHelloFlags.hello) != 0,
                onChanged: (v) => setState(() {
                  _helloFlags = (v == true)
                      ? (_helloFlags | PixelHelloFlags.hello)
                      : (_helloFlags & ~PixelHelloFlags.hello);
                }),
              ),
              CheckboxListTile(
                title: const Text('On Goodbye (sleep)'),
                value: (_helloFlags & PixelHelloFlags.goodbye) != 0,
                onChanged: (v) => setState(() {
                  _helloFlags = (v == true)
                      ? (_helloFlags | PixelHelloFlags.goodbye)
                      : (_helloFlags & ~PixelHelloFlags.goodbye);
                }),
              ),
            ],
            if (_condType == _CondType.crooked) ...[
              const SizedBox(height: 8),
              const Text(
                'Fires when the die lands but is not flat on a face.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_condType == _CondType.idle) ...[
              const SizedBox(height: 8),
              Text('Repeat period: ${_idlePeriodMs == 0 ? "once" : "$_idlePeriodMs ms"}'),
              Slider(
                value: _idlePeriodMs.toDouble(),
                min: 0, max: 30000,
                divisions: 30,
                onChanged: (v) => setState(() => _idlePeriodMs = v.round()),
              ),
            ],
            if (_condType == _CondType.battery) ...[
              const SizedBox(height: 8),
              for (final (flag, label) in const [
                (PixelBatteryFlags.low, 'Low'),
                (PixelBatteryFlags.charging, 'Charging'),
                (PixelBatteryFlags.done, 'Fully charged'),
                (PixelBatteryFlags.badCharging, 'Bad charging'),
                (PixelBatteryFlags.error, 'Error'),
              ])
                CheckboxListTile(
                  dense: true,
                  title: Text(label),
                  value: (_battFlags & flag) != 0,
                  onChanged: (v) => setState(() {
                    _battFlags = (v == true) ? (_battFlags | flag) : (_battFlags & ~flag);
                  }),
                ),
              Text('Recheck period: $_battPeriodMs ms'),
              Slider(
                value: _battPeriodMs.toDouble(),
                min: 0, max: 30000,
                divisions: 30,
                onChanged: (v) => setState(() => _battPeriodMs = v.round()),
              ),
            ],
            if (_condType == _CondType.connection) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                title: const Text('On connect'),
                value: (_connFlags & PixelConnectionFlags.connected) != 0,
                onChanged: (v) => setState(() {
                  _connFlags = (v == true)
                      ? (_connFlags | PixelConnectionFlags.connected)
                      : (_connFlags & ~PixelConnectionFlags.connected);
                }),
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('On disconnect'),
                value: (_connFlags & PixelConnectionFlags.disconnected) != 0,
                onChanged: (v) => setState(() {
                  _connFlags = (v == true)
                      ? (_connFlags | PixelConnectionFlags.disconnected)
                      : (_connFlags & ~PixelConnectionFlags.disconnected);
                }),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Action', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (widget.animationCount > 0) ...[
              DropdownButtonFormField<int>(
                value: _animIndex.clamp(0, widget.animationCount - 1),
                decoration: const InputDecoration(labelText: 'Play Animation'),
                items: List.generate(widget.animationCount, (i) => DropdownMenuItem(
                  value: i,
                  child: Text('Animation ${i + 1}'),
                )),
                onChanged: (v) { if (v != null) setState(() => _animIndex = v); },
              ),
              const SizedBox(height: 8),
              Text('Loop count: $_loopCount'),
              Slider(
                value: _loopCount.toDouble(),
                min: 1, max: 10,
                divisions: 9,
                onChanged: (v) => setState(() => _loopCount = v.round()),
              ),
            ] else
              const Text('(No animations — add one first)', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        // A rule's only action is "play animation", so it's meaningless without
        // at least one animation to point at.
        TextButton(
          onPressed: widget.animationCount == 0 ? null : () => Navigator.pop(context, _build()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Grid of face toggle chips for building a face bitmask.
class _FaceMaskChips extends StatelessWidget {
  const _FaceMaskChips({
    required this.mask,
    required this.faces,
    required this.onChanged,
  });

  final int mask;
  final int faces;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(faces, (i) {
        final bit = 1 << i;
        final selected = (mask & bit) != 0;
        return FilterChip(
          label: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
          selected: selected,
          onSelected: (_) => onChanged(selected ? mask & ~bit : mask | bit),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        );
      }),
    );
  }
}
