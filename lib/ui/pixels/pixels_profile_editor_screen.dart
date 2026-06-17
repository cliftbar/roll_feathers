import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:roll_feathers/dice_sdks/pixels_animation.dart';

/// Edits a single [PixelProfile]: name, list of animations, list of rules.
///
/// Returns the updated [PixelProfile] via [Navigator.pop] when saved,
/// or null when cancelled.
class PixelsProfileEditorScreen extends StatefulWidget {
  const PixelsProfileEditorScreen({super.key, required this.profile});

  final PixelProfile profile;

  @override
  State<PixelsProfileEditorScreen> createState() => _PixelsProfileEditorScreenState();
}

class _PixelsProfileEditorScreenState extends State<PixelsProfileEditorScreen> {
  late TextEditingController _nameCtrl;
  late List<PixelAnimation> _animations;
  late List<PixelRule> _rules;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name);
    _animations = List.of(widget.profile.animations);
    _rules = List.of(widget.profile.rules);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  PixelProfile _buildProfile() => PixelProfile(
    id: widget.profile.id,
    name: _nameCtrl.text.trim().isEmpty ? 'Unnamed' : _nameCtrl.text.trim(),
    brightness: widget.profile.brightness,
    animations: List.of(_animations),
    rules: List.of(_rules),
  );

  void _save() => Navigator.of(context).pop(_buildProfile());

  // ── Animations ────────────────────────────────────────────────────────────

  Future<void> _addAnimation() async {
    final result = await _showAnimationEditor(null);
    if (result != null) setState(() => _animations.add(result));
  }

  Future<void> _editAnimation(int index) async {
    final result = await _showAnimationEditor(_animations[index]);
    if (result != null) setState(() => _animations[index] = result);
  }

  void _deleteAnimation(int index) {
    setState(() {
      _animations.removeAt(index);
      // Fix any rules that reference a deleted animation index.
      _rules = _rules.map((r) {
        final fixed = r.actions.map((a) {
          if (a is PixelActionPlayAnimation && a.animIndex >= _animations.length) {
            return PixelActionPlayAnimation(animIndex: (_animations.length - 1).clamp(0, 255));
          }
          return a;
        }).toList();
        return PixelRule(condition: r.condition, actions: fixed);
      }).toList();
    });
  }

  Future<PixelAnimation?> _showAnimationEditor(PixelAnimation? existing) {
    return showDialog<PixelAnimation>(
      context: context,
      builder: (_) => _AnimationEditorDialog(animation: existing),
    );
  }

  // ── Rules ─────────────────────────────────────────────────────────────────

  Future<void> _addRule() async {
    if (_animations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one animation first')),
      );
      return;
    }
    final result = await _showRuleEditor(null);
    if (result != null) setState(() => _rules.add(result));
  }

  Future<void> _editRule(int index) async {
    final result = await _showRuleEditor(_rules[index]);
    if (result != null) setState(() => _rules[index] = result);
  }

  void _deleteRule(int index) => setState(() => _rules.removeAt(index));

  Future<PixelRule?> _showRuleEditor(PixelRule? existing) {
    return showDialog<PixelRule>(
      context: context,
      builder: (_) => _RuleEditorDialog(
        rule: existing,
        animationCount: _animations.length,
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
      body: ListView(
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
                onPressed: _addAnimation,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_animations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No animations yet.', style: TextStyle(color: Colors.grey)),
            ),
          ...List.generate(_animations.length, (i) {
            final anim = _animations[i];
            return Card(
              child: ListTile(
                leading: _AnimationIcon(anim),
                title: Text(_animLabel(i, anim)),
                subtitle: Text(_animSubtitle(anim)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editAnimation(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteAnimation(i),
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
          if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No rules yet.', style: TextStyle(color: Colors.grey)),
            ),
          ...List.generate(_rules.length, (i) {
            final rule = _rules[i];
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
                      onPressed: () => _deleteRule(i),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _animLabel(int i, PixelAnimation anim) => 'Animation ${i + 1}: ${_animTypeName(anim)}';

  String _animTypeName(PixelAnimation anim) => switch (anim) {
    PixelAnimationSimple _ => 'Solid Flash',
    PixelAnimationRainbow _ => 'Rainbow',
    PixelAnimationKeyframed _ => 'Keyframed',
    _ => 'Unknown',
  };

  String _animSubtitle(PixelAnimation anim) => switch (anim) {
    PixelAnimationSimple s =>
      '${s.durationMs}ms · color(${s.color.r},${s.color.g},${s.color.b}) · ×${s.count}',
    PixelAnimationRainbow r => '${r.durationMs}ms · intensity ${r.intensity}',
    PixelAnimationKeyframed _ => 'Keyframed',
    _ => '',
  };

  String _ruleSubtitle(PixelRule rule) {
    final actions = rule.actions.map((a) {
      if (a is PixelActionPlayAnimation) return 'Play animation ${a.animIndex + 1}';
      return 'Action';
    }).join(', ');
    return 'Then: $actions';
  }
}

class _AnimationIcon extends StatelessWidget {
  const _AnimationIcon(this.anim);
  final PixelAnimation anim;

  @override
  Widget build(BuildContext context) {
    if (anim is PixelAnimationSimple) {
      final c = (anim as PixelAnimationSimple).color;
      return CircleAvatar(backgroundColor: Color.fromARGB(255, c.r, c.g, c.b));
    }
    if (anim is PixelAnimationRainbow) {
      return const CircleAvatar(
        child: Icon(Icons.auto_awesome, size: 16),
      );
    }
    return const CircleAvatar(child: Icon(Icons.timeline, size: 16));
  }
}

// ─── Animation editor dialog ──────────────────────────────────────────────────

enum _AnimType { solid, rainbow }

class _AnimationEditorDialog extends StatefulWidget {
  const _AnimationEditorDialog({this.animation});
  final PixelAnimation? animation;

  @override
  State<_AnimationEditorDialog> createState() => _AnimationEditorDialogState();
}

class _AnimationEditorDialogState extends State<_AnimationEditorDialog> {
  late _AnimType _type;
  // Solid fields
  int _r = 255, _g = 0, _b = 0;
  int _durationMs = 500;
  int _count = 1;
  int _fade = 128;
  // Rainbow fields
  int _rainbowDuration = 2000;
  int _intensity = 200;

  @override
  void initState() {
    super.initState();
    final a = widget.animation;
    if (a is PixelAnimationRainbow) {
      _type = _AnimType.rainbow;
      _rainbowDuration = a.durationMs;
      _intensity = a.intensity;
    } else {
      _type = _AnimType.solid;
      if (a is PixelAnimationSimple) {
        _r = a.color.r;
        _g = a.color.g;
        _b = a.color.b;
        _durationMs = a.durationMs;
        _count = a.count;
        _fade = a.fade;
      }
    }
  }

  PixelAnimation _build() {
    if (_type == _AnimType.rainbow) {
      return PixelAnimationRainbow(durationMs: _rainbowDuration, intensity: _intensity);
    }
    return PixelAnimationSimple(
      durationMs: _durationMs,
      color: PixelColor(_r, _g, _b),
      count: _count,
      fade: _fade,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Animation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_AnimType>(
              segments: const [
                ButtonSegment(value: _AnimType.solid, label: Text('Solid Flash')),
                ButtonSegment(value: _AnimType.rainbow, label: Text('Rainbow')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
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
                      min: 0,
                      max: 255,
                      onChanged: (v) => setState(() => _fade = v.round()),
                    ),
                  ),
                  Text('$_fade'),
                ],
              ),
              const SizedBox(height: 8),
              // Color preview
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, _r, _g, _b),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                ),
              ),
            ],
            if (_type == _AnimType.rainbow) ...[
              _intField('Duration (ms)', _rainbowDuration, 100, 10000, (v) => _rainbowDuration = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Intensity'),
                  Expanded(
                    child: Slider(
                      value: _intensity.toDouble(),
                      min: 0,
                      max: 255,
                      onChanged: (v) => setState(() => _intensity = v.round()),
                    ),
                  ),
                  Text('$_intensity'),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _build()), child: const Text('OK')),
      ],
    );
  }

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

enum _CondType { rolled, rolling, helloGoodbye, handling }

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
  int _helloFlags = 3; // both hello and goodbye

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
      } else {
        _condType = _CondType.handling;
      }
      final action = rule.actions.whereType<PixelActionPlayAnimation>().firstOrNull;
      if (action != null) {
        _animIndex = action.animIndex.clamp(0, widget.animationCount - 1);
        _loopCount = action.loopCount;
      }
    }
  }

  PixelRule _build() {
    final PixelCondition cond = switch (_condType) {
      _CondType.rolled => PixelConditionRolled(faceMask: _faceMask),
      _CondType.rolling => PixelConditionRolling(repeatPeriodMs: _rollingPeriodMs),
      _CondType.helloGoodbye => PixelConditionHelloGoodbye(flags: _helloFlags),
      _CondType.handling => PixelConditionHandling(),
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
                DropdownMenuItem(value: _CondType.rolled, child: Text('Rolled (face landed)')),
                DropdownMenuItem(value: _CondType.rolling, child: Text('Rolling (in motion)')),
                DropdownMenuItem(value: _CondType.helloGoodbye, child: Text('Hello / Goodbye')),
                DropdownMenuItem(value: _CondType.handling, child: Text('Handling (picked up)')),
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
                min: 100,
                max: 2000,
                divisions: 19,
                onChanged: (v) => setState(() => _rollingPeriodMs = v.round()),
              ),
            ],
            if (_condType == _CondType.helloGoodbye) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('On Hello (wake up)'),
                value: (_helloFlags & 1) != 0,
                onChanged: (v) => setState(() {
                  _helloFlags = (v == true) ? (_helloFlags | 1) : (_helloFlags & ~1);
                }),
              ),
              CheckboxListTile(
                title: const Text('On Goodbye (sleep)'),
                value: (_helloFlags & 2) != 0,
                onChanged: (v) => setState(() {
                  _helloFlags = (v == true) ? (_helloFlags | 2) : (_helloFlags & ~2);
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
                min: 1,
                max: 10,
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
        TextButton(onPressed: () => Navigator.pop(context, _build()), child: const Text('OK')),
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
