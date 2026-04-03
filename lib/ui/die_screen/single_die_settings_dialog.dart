import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart';

enum _ColorMode {
  hexWheel('Hex / Wheel'),
  rgbSliders('RGB / Sliders'),
  hsvSquare('HSV / Square'),
  hslSquare('HSL / Square');

  const _ColorMode(this.label);
  final String label;
}

class SingleDieSettingsDialog extends StatefulWidget {
  const SingleDieSettingsDialog({
    super.key,
    required this.die,
    required this.haEnabled,
    required this.onBlink,
    required this.onDisconnect,
    required this.onSave,
  });

  final GenericDie die;
  final bool haEnabled;
  final Future<void> Function(Color, GenericDie, String?) onBlink;
  final Future<void> Function(String) onDisconnect;
  final Future<void> Function(GenericDie, Color, String, GenericDType) onSave;

  @override
  State<SingleDieSettingsDialog> createState() => _SingleDieSettingsDialogState();
}

class _SingleDieSettingsDialogState extends State<SingleDieSettingsDialog> {
  // Color state — HSVColor is the single source of truth
  late HSVColor _currentColor;
  _ColorMode _colorMode = _ColorMode.hexWheel;

  // Hex
  final _hexCtrl = TextEditingController();
  final _hexFocus = FocusNode();

  // RGB
  final _rCtrl = TextEditingController();
  final _gCtrl = TextEditingController();
  final _bCtrl = TextEditingController();
  final _rFocus = FocusNode();
  final _gFocus = FocusNode();
  final _bFocus = FocusNode();

  // HSV
  final _hsvHCtrl = TextEditingController();
  final _hsvSCtrl = TextEditingController();
  final _hsvVCtrl = TextEditingController();
  final _hsvHFocus = FocusNode();
  final _hsvSFocus = FocusNode();
  final _hsvVFocus = FocusNode();

  // HSL
  final _hslHCtrl = TextEditingController();
  final _hslSCtrl = TextEditingController();
  final _hslLCtrl = TextEditingController();
  final _hslHFocus = FocusNode();
  final _hslSFocus = FocusNode();
  final _hslLFocus = FocusNode();

  late TextEditingController _entityController;
  late GenericDType _currentFaceType;

  @override
  void initState() {
    super.initState();
    _currentColor = HSVColor.fromColor(widget.die.blinkColor ?? Colors.white);
    _entityController = TextEditingController(text: widget.die.haEntityTargets.firstOrNull ?? '');
    _currentFaceType = widget.die.dType;
    _updateControllers();
    // Restore any field left empty/invalid when focus leaves it.
    for (final node in [
      _hexFocus, _rFocus, _gFocus, _bFocus,
      _hsvHFocus, _hsvSFocus, _hsvVFocus,
      _hslHFocus, _hslSFocus, _hslLFocus,
    ]) {
      node.addListener(() { if (!node.hasFocus) _updateControllers(); });
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _hexFocus.dispose();
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _rFocus.dispose();
    _gFocus.dispose();
    _bFocus.dispose();
    _hsvHCtrl.dispose();
    _hsvSCtrl.dispose();
    _hsvVCtrl.dispose();
    _hsvHFocus.dispose();
    _hsvSFocus.dispose();
    _hsvVFocus.dispose();
    _hslHCtrl.dispose();
    _hslSCtrl.dispose();
    _hslLCtrl.dispose();
    _hslHFocus.dispose();
    _hslSFocus.dispose();
    _hslLFocus.dispose();
    _entityController.dispose();
    super.dispose();
  }

  // ── Color sync ────────────────────────────────────────────────────────────

  void _onHsvColorChanged(HSVColor hsv) {
    setState(() => _currentColor = hsv);
    _updateControllers();
  }

  /// Updates every controller that doesn't currently have focus, so
  /// the user's in-progress edits are never overwritten mid-keystroke.
  void _updateControllers() {
    final color = _currentColor.toColor();
    final hsl = hsvToHsl(_currentColor);
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();

    if (!_hexFocus.hasFocus) {
      _hexCtrl.text = colorToHex(color, enableAlpha: false);
    }
    if (!_rFocus.hasFocus) _rCtrl.text = r.toString();
    if (!_gFocus.hasFocus) _gCtrl.text = g.toString();
    if (!_bFocus.hasFocus) _bCtrl.text = b.toString();
    if (!_hsvHFocus.hasFocus) _hsvHCtrl.text = _currentColor.hue.round().toString();
    if (!_hsvSFocus.hasFocus) _hsvSCtrl.text = (_currentColor.saturation * 100).round().toString();
    if (!_hsvVFocus.hasFocus) _hsvVCtrl.text = (_currentColor.value * 100).round().toString();
    if (!_hslHFocus.hasFocus) _hslHCtrl.text = hsl.hue.round().toString();
    if (!_hslSFocus.hasFocus) _hslSCtrl.text = (hsl.saturation * 100).round().toString();
    if (!_hslLFocus.hasFocus) _hslLCtrl.text = (hsl.lightness * 100).round().toString();
  }

  // ── Field change handlers ─────────────────────────────────────────────────

  void _onHexFieldChanged(String val) {
    final color = colorFromHex(val, enableAlpha: false);
    if (color != null) _onHsvColorChanged(HSVColor.fromColor(color));
  }

  void _onRFieldChanged(String val) {
    final r = int.tryParse(val);
    if (r != null && r <= 255) {
      final c = _currentColor.toColor();
      _onHsvColorChanged(HSVColor.fromColor(Color.fromRGBO(r, (c.g * 255).round(), (c.b * 255).round(), 1)));
    }
  }

  void _onGFieldChanged(String val) {
    final g = int.tryParse(val);
    if (g != null && g <= 255) {
      final c = _currentColor.toColor();
      _onHsvColorChanged(HSVColor.fromColor(Color.fromRGBO((c.r * 255).round(), g, (c.b * 255).round(), 1)));
    }
  }

  void _onBFieldChanged(String val) {
    final b = int.tryParse(val);
    if (b != null && b <= 255) {
      final c = _currentColor.toColor();
      _onHsvColorChanged(HSVColor.fromColor(Color.fromRGBO((c.r * 255).round(), (c.g * 255).round(), b, 1)));
    }
  }

  void _onHsvHFieldChanged(String val) {
    final h = double.tryParse(val);
    if (h != null && h <= 360) _onHsvColorChanged(_currentColor.withHue(h));
  }

  void _onHsvSFieldChanged(String val) {
    final s = int.tryParse(val);
    if (s != null && s <= 100) _onHsvColorChanged(_currentColor.withSaturation(s / 100));
  }

  void _onHsvVFieldChanged(String val) {
    final v = int.tryParse(val);
    if (v != null && v <= 100) _onHsvColorChanged(_currentColor.withValue(v / 100));
  }

  void _onHslHFieldChanged(String val) {
    final h = double.tryParse(val);
    if (h != null && h <= 360) _onHsvColorChanged(hslToHsv(hsvToHsl(_currentColor).withHue(h)));
  }

  void _onHslSFieldChanged(String val) {
    final s = int.tryParse(val);
    if (s != null && s <= 100) _onHsvColorChanged(hslToHsv(hsvToHsl(_currentColor).withSaturation(s / 100)));
  }

  void _onHslLFieldChanged(String val) {
    final l = int.tryParse(val);
    if (l != null && l <= 100) _onHsvColorChanged(hslToHsv(hsvToHsl(_currentColor).withLightness(l / 100)));
  }

  // ── Picker widgets ────────────────────────────────────────────────────────

  Widget _buildVisualPicker() {
    switch (_colorMode) {
      case _ColorMode.hexWheel:
      case _ColorMode.hsvSquare:
      case _ColorMode.hslSquare:
        return ColorPicker(
          pickerColor: _currentColor.toColor(),
          // flutter_colorpicker requires onColorChanged but we use onHsvColorChanged
          // as the single source of truth to avoid a double-conversion round-trip.
          onColorChanged: (_) {},
          onHsvColorChanged: _onHsvColorChanged,
          paletteType: switch (_colorMode) {
            _ColorMode.hsvSquare => PaletteType.hsvWithHue,
            _ColorMode.hslSquare => PaletteType.hslWithHue,
            _ => PaletteType.hueWheel,
          },
          labelTypes: const [],
          hexInputBar: false,
          enableAlpha: false,
          pickerAreaHeightPercent: 0.7,
          portraitOnly: true,
        );
      case _ColorMode.rgbSliders:
        final color = _currentColor.toColor();
        final r = (color.r * 255).round().toDouble();
        final g = (color.g * 255).round().toDouble();
        final b = (color.b * 255).round().toDouble();
        return Column(
          children: [
            _gradientSlider(value: r, startColor: Colors.black, endColor: Colors.red,
                thumbColor: color, onChanged: (v) => _onRFieldChanged(v.round().toString())),
            _gradientSlider(value: g, startColor: Colors.black, endColor: Colors.green,
                thumbColor: color, onChanged: (v) => _onGFieldChanged(v.round().toString())),
            _gradientSlider(value: b, startColor: Colors.black, endColor: Colors.blue,
                thumbColor: color, onChanged: (v) => _onBFieldChanged(v.round().toString())),
          ],
        );
    }
  }

  Widget _buildNumericInputs() {
    switch (_colorMode) {
      case _ColorMode.hexWheel:
        return _inputRow([
          _field(
            label: 'Hex',
            prefix: '#',
            controller: _hexCtrl,
            focusNode: _hexFocus,
            onChanged: _onHexFieldChanged,
            width: 110,
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(6),
            ],
          ),
        ]);
      case _ColorMode.rgbSliders:
        return _inputRow([
          _field(label: 'R', controller: _rCtrl, focusNode: _rFocus, onChanged: _onRFieldChanged, formatters: _intFormatters),
          _field(label: 'G', controller: _gCtrl, focusNode: _gFocus, onChanged: _onGFieldChanged, formatters: _intFormatters),
          _field(label: 'B', controller: _bCtrl, focusNode: _bFocus, onChanged: _onBFieldChanged, formatters: _intFormatters),
        ]);
      case _ColorMode.hsvSquare:
        return _inputRow([
          _field(label: 'H', controller: _hsvHCtrl, focusNode: _hsvHFocus, onChanged: _onHsvHFieldChanged, suffix: '°', formatters: _intFormatters),
          _field(label: 'S', controller: _hsvSCtrl, focusNode: _hsvSFocus, onChanged: _onHsvSFieldChanged, suffix: '%', formatters: _intFormatters),
          _field(label: 'V', controller: _hsvVCtrl, focusNode: _hsvVFocus, onChanged: _onHsvVFieldChanged, suffix: '%', formatters: _intFormatters),
        ]);
      case _ColorMode.hslSquare:
        return _inputRow([
          _field(label: 'H', controller: _hslHCtrl, focusNode: _hslHFocus, onChanged: _onHslHFieldChanged, suffix: '°', formatters: _intFormatters),
          _field(label: 'S', controller: _hslSCtrl, focusNode: _hslSFocus, onChanged: _onHslSFieldChanged, suffix: '%', formatters: _intFormatters),
          _field(label: 'L', controller: _hslLCtrl, focusNode: _hslLFocus, onChanged: _onHslLFieldChanged, suffix: '%', formatters: _intFormatters),
        ]);
    }
  }

  static final List<TextInputFormatter> _intFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(3),
  ];

  Widget _inputRow(List<Widget> fields) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: fields,
        ),
      );

  Widget _field({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required void Function(String) onChanged,
    required List<TextInputFormatter> formatters,
    String? suffix,
    String? prefix,
    double width = 65,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: width,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              prefixText: prefix,
              isDense: true,
            ),
            inputFormatters: formatters,
          ),
        ),
      );

  // ── Gradient slider ───────────────────────────────────────────────────────

  Widget _gradientSlider({
    required double value,
    required Color startColor,
    required Color endColor,
    required Color thumbColor,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackShape: _GradientTrackShape(start: startColor, end: endColor),
        thumbColor: thumbColor,
        overlayColor: thumbColor.withValues(alpha: 0.2),
        trackHeight: 16,
      ),
      child: Slider(value: value, min: 0, max: 255, onChanged: onChanged),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Use Dialog + ConstrainedBox rather than AlertDialog, because AlertDialog
    // wraps content in IntrinsicWidth which propagates intrinsic dimension
    // queries down to DropdownMenu's LayoutBuilder — crashing in debug mode.
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row — Disconnect icon lives here, far from Save.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.die.friendlyName} Settings',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Disconnect',
                    color: Theme.of(context).colorScheme.error,
                    onPressed: () {
                      widget.onDisconnect(widget.die.dieId);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Color first — it's the primary action.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Swatch fills remaining space — always as wide as possible.
                          Expanded(
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: _currentColor.toColor(),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                            ),
                          ),
                          // Preview: flash the die with the current color.
                          TextButton.icon(
                            icon: const Icon(Icons.flash_on),
                            label: const Text('Preview'),
                            onPressed: () => widget.onBlink(
                                _currentColor.toColor(), widget.die, _entityController.text),
                          ),
                          DropdownMenu<_ColorMode>(
                            initialSelection: _colorMode,
                            width: 165,
                            enableSearch: false,
                            onSelected: (mode) {
                              if (mode != null) {
                                setState(() => _colorMode = mode);
                                FocusScope.of(context).unfocus();
                              }
                            },
                            dropdownMenuEntries: _ColorMode.values
                                .map((m) => DropdownMenuEntry(value: m, label: m.label))
                                .toList(),
                          ),
                        ],
                      ),
                      _buildVisualPicker(),
                      _buildNumericInputs(),
                      const Divider(),
                      // Face count below the color section.
                      const Text('Face Count'),
                      _FaceSelector(
                        die: widget.die,
                        onChanged: (t) => _currentFaceType = t,
                      ),
                      // HA entity only rendered when integration is enabled.
                      if (widget.haEnabled) ...[
                        const Divider(),
                        TextField(
                          controller: _entityController,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Home Assistant Entity',
                            hintText: 'light.bedroom',
                            helperText: 'Leave empty to use default entity',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    child: const Text('Save'),
                    onPressed: () {
                      widget.onSave(widget.die, _currentColor.toColor(), _entityController.text, _currentFaceType);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Face selector ─────────────────────────────────────────────────────────────

class _FaceSelector extends StatefulWidget {
  const _FaceSelector({required this.die, required this.onChanged});

  final GenericDie die;
  final ValueChanged<GenericDType> onChanged;

  @override
  State<_FaceSelector> createState() => _FaceSelectorState();
}

class _FaceSelectorState extends State<_FaceSelector> {
  // Only allocated for virtual dice; null for all other types.
  TextEditingController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.die.type == GenericDieType.virtual) {
      _controller = TextEditingController(text: '${widget.die.dType.faces}');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.die.type) {
      case GenericDieType.pixel:
        return Text(widget.die.dType.name);

      case GenericDieType.godice:
        return DropdownMenu<String>(
          initialSelection: GodiceDieType.fromName(widget.die.dType.name).name,
          onSelected: (value) {
            if (value != null) {
              widget.onChanged(GodiceDieType.fromName(value).toDType());
            }
          },
          dropdownMenuEntries: GodiceDieType.values
              .where((t) => t != GodiceDieType.d24)
              .map((v) => DropdownMenuEntry<String>(value: v.name, label: v.name))
              .toList(),
        );

      case GenericDieType.virtual:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Number of Faces',
                hintText: 'Enter the number of faces',
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) {
                final faces = int.tryParse(val);
                if (faces != null) {
                  final dType = GenericDTypeFactory.fromIntId(faces) ??
                      GenericDType('d$faces', faces, faces, 0, 1);
                  widget.onChanged(dType);
                }
              },
            ),
          ],
        );
    }
  }
}

// ── Gradient track shape for RGB sliders ──────────────────────────────────────

class _GradientTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final Color start;
  final Color end;

  const _GradientTrackShape({required this.start, required this.end});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    required TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(trackRect.height / 2)),
      Paint()
        ..shader = LinearGradient(colors: [start, end]).createShader(trackRect),
    );
  }
}

@Preview(name: 'SingleDieSettingsDialog - virtual die')
Widget singleDieSettingsVirtual() {
  final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d6'), name: 'Red D6');
  die.blinkColor = Colors.red;
  return MaterialApp(
    home: Scaffold(
      body: SingleDieSettingsDialog(
        die: die,
        haEnabled: true,
        onBlink: (_, __, ___) async {},
        onDisconnect: (_) async {},
        onSave: (_, __, ___, ____) async {},
      ),
    ),
  );
}

@Preview(name: 'SingleDieSettingsDialog - HA disabled')
Widget singleDieSettingsNoHa() {
  final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d20'), name: 'Blue D20');
  return MaterialApp(
    home: Scaffold(
      body: SingleDieSettingsDialog(
        die: die,
        haEnabled: false,
        onBlink: (_, __, ___) async {},
        onDisconnect: (_) async {},
        onSave: (_, __, ___, ____) async {},
      ),
    ),
  );
}
