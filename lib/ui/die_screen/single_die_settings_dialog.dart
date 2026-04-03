import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart';
import 'package:tuple/tuple.dart';

enum _ColorMode {
  hexWheel('Hex / Wheel'),
  rgbSliders('ARGB / Sliders'),
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
  late HSVColor _hsvColor;
  _ColorMode _colorMode = _ColorMode.hexWheel;

  // Hex
  final _hexCtrl = TextEditingController();
  final _hexFocus = FocusNode();

  // RGB + Alpha
  final _rCtrl = TextEditingController();
  final _gCtrl = TextEditingController();
  final _bCtrl = TextEditingController();
  final _aCtrl = TextEditingController();
  final _rFocus = FocusNode();
  final _gFocus = FocusNode();
  final _bFocus = FocusNode();
  final _aFocus = FocusNode();

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
  late Tuple2<Widget, ValueGetter<GenericDType>> _faceTuple;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.die.blinkColor ?? Colors.white);
    _entityController = TextEditingController(text: widget.die.haEntityTargets.firstOrNull ?? '');
    _faceTuple = _makeFaceSelectorWidget(widget.die);
    _updateControllers();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _hexFocus.dispose();
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _aCtrl.dispose();
    _rFocus.dispose();
    _gFocus.dispose();
    _bFocus.dispose();
    _aFocus.dispose();
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
    setState(() => _hsvColor = hsv);
    _updateControllers();
  }

  /// Updates every controller that doesn't currently have focus, so
  /// the user's in-progress edits are never overwritten mid-keystroke.
  void _updateControllers() {
    final color = _hsvColor.toColor();
    final hsl = hsvToHsl(_hsvColor);
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();

    if (!_hexFocus.hasFocus) {
      _hexCtrl.text = colorToHex(color, enableAlpha: false);
    }
    if (!_rFocus.hasFocus) _rCtrl.text = r.toString();
    if (!_gFocus.hasFocus) _gCtrl.text = g.toString();
    if (!_bFocus.hasFocus) _bCtrl.text = b.toString();
    if (!_aFocus.hasFocus) _aCtrl.text = (_hsvColor.alpha * 255).round().toString();
    if (!_hsvHFocus.hasFocus) _hsvHCtrl.text = _hsvColor.hue.round().toString();
    if (!_hsvSFocus.hasFocus) _hsvSCtrl.text = (_hsvColor.saturation * 100).round().toString();
    if (!_hsvVFocus.hasFocus) _hsvVCtrl.text = (_hsvColor.value * 100).round().toString();
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
      final c = _hsvColor.toColor();
      _onHsvColorChanged(HSVColor.fromColor(Color.fromRGBO(r, (c.g * 255).round(), (c.b * 255).round(), 1)));
    }
  }

  void _onGFieldChanged(String val) {
    final g = int.tryParse(val);
    if (g != null && g <= 255) {
      final c = _hsvColor.toColor();
      _onHsvColorChanged(HSVColor.fromColor(Color.fromRGBO((c.r * 255).round(), g, (c.b * 255).round(), 1)));
    }
  }

  void _onBFieldChanged(String val) {
    final b = int.tryParse(val);
    if (b != null && b <= 255) {
      final c = _hsvColor.toColor();
      _onHsvColorChanged(HSVColor.fromColor(Color.fromRGBO((c.r * 255).round(), (c.g * 255).round(), b, 1)));
    }
  }

  void _onAFieldChanged(String val) {
    final a = int.tryParse(val);
    if (a != null && a <= 255) _onHsvColorChanged(_hsvColor.withAlpha(a / 255));
  }

  void _onHsvHFieldChanged(String val) {
    final h = double.tryParse(val);
    if (h != null && h <= 360) _onHsvColorChanged(_hsvColor.withHue(h));
  }

  void _onHsvSFieldChanged(String val) {
    final s = int.tryParse(val);
    if (s != null && s <= 100) _onHsvColorChanged(_hsvColor.withSaturation(s / 100));
  }

  void _onHsvVFieldChanged(String val) {
    final v = int.tryParse(val);
    if (v != null && v <= 100) _onHsvColorChanged(_hsvColor.withValue(v / 100));
  }

  void _onHslHFieldChanged(String val) {
    final h = double.tryParse(val);
    if (h != null && h <= 360) _onHsvColorChanged(hslToHsv(hsvToHsl(_hsvColor).withHue(h)));
  }

  void _onHslSFieldChanged(String val) {
    final s = int.tryParse(val);
    if (s != null && s <= 100) _onHsvColorChanged(hslToHsv(hsvToHsl(_hsvColor).withSaturation(s / 100)));
  }

  void _onHslLFieldChanged(String val) {
    final l = int.tryParse(val);
    if (l != null && l <= 100) _onHsvColorChanged(hslToHsv(hsvToHsl(_hsvColor).withLightness(l / 100)));
  }

  // ── Picker widgets ────────────────────────────────────────────────────────

  Widget _buildVisualPicker() {
    switch (_colorMode) {
      case _ColorMode.hexWheel:
      case _ColorMode.hsvSquare:
      case _ColorMode.hslSquare:
        return ColorPicker(
          pickerColor: _hsvColor.toColor(),
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
        final color = _hsvColor.toColor();
        final r = (color.r * 255).round().toDouble();
        final g = (color.g * 255).round().toDouble();
        final b = (color.b * 255).round().toDouble();
        final a = (_hsvColor.alpha * 255).round().toDouble();
        // Opaque current color (for alpha slider end and thumb)
        final opaqueColor = _hsvColor.withAlpha(1.0).toColor();
        return Column(
          children: [
            _gradientSlider(value: r, startColor: Colors.black, endColor: Colors.red,
                thumbColor: color, onChanged: (v) => _onRFieldChanged(v.round().toString())),
            _gradientSlider(value: g, startColor: Colors.black, endColor: Colors.green,
                thumbColor: color, onChanged: (v) => _onGFieldChanged(v.round().toString())),
            _gradientSlider(value: b, startColor: Colors.black, endColor: Colors.blue,
                thumbColor: color, onChanged: (v) => _onBFieldChanged(v.round().toString())),
            _gradientSlider(value: a, startColor: Colors.transparent, endColor: opaqueColor,
                thumbColor: color, onChanged: (v) => _onAFieldChanged(v.round().toString())),
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
          _field(label: 'A', controller: _aCtrl, focusNode: _aFocus, onChanged: _onAFieldChanged, formatters: _intFormatters),
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
            keyboardType: TextInputType.number,
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

  // ── Face selector (unchanged) ─────────────────────────────────────────────

  // this is a bad pattern x.x
  Tuple2<Widget, ValueGetter<GenericDType>> _makeFaceSelectorWidget(GenericDie die) {
    switch (die.type) {
      case GenericDieType.pixel:
        faceCallback() => die.dType;
        return Tuple2(Text(die.dType.name), faceCallback);
      case GenericDieType.godice:
        final List<DropdownMenuEntry<String>> menuEntries = UnmodifiableListView<DropdownMenuEntry<String>>(
          GodiceDieType.values
              .where((t) => t != GodiceDieType.d24)
              .map<DropdownMenuEntry<String>>(
                (GodiceDieType v) => DropdownMenuEntry<String>(value: v.name, label: v.name),
              ),
        );
        GenericDType dropdownValue = die.dType;
        var menu = DropdownMenu<String>(
          initialSelection: GodiceDieType.fromName(die.dType.name).name,
          onSelected: (String? value) {
            if (value != null) {
              dropdownValue = GodiceDieType.fromName(value).toDType();
            }
          },
          dropdownMenuEntries: menuEntries,
        );
        faceCallback() => dropdownValue;
        return Tuple2(menu, faceCallback);
      case GenericDieType.virtual:
        var faceCountUpdateController = TextEditingController(text: '${die.dType.faces}');
        faceCallback() {
          int value = int.parse(faceCountUpdateController.text);
          var dType = GenericDTypeFactory.fromIntId(value) ?? GenericDType('d${value.toString()}', value, value, 0, 1);
          return dType;
        }
        var col = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            TextFormField(
              controller: faceCountUpdateController,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Number of Faces', hintText: 'Enter the number of faces'),
              keyboardType: TextInputType.number,
            ),
          ],
        );
        return Tuple2(col, faceCallback);
    }
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
              Text(
                '${widget.die.friendlyName} Settings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Face Count'),
                      _faceTuple.item1,
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Option A: color dot inline with the label.
                          // Options B/C/D: thin bar, chip in ARGB row, or accent divider.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Color'),
                              const SizedBox(width: 8),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _hsvColor.toColor(),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade400),
                                ),
                              ),
                            ],
                          ),
                          DropdownMenu<_ColorMode>(
                            initialSelection: _colorMode,
                            width: 185,
                            enableSearch: false,
                            onSelected: (mode) {
                              if (mode != null) setState(() => _colorMode = mode);
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
                      TextField(
                        controller: _entityController,
                        enabled: widget.haEnabled,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Home Assistant Entity',
                          hintText: 'light.bedroom',
                          helperText: 'Leave empty to use default entity',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions — OverflowBar wraps buttons onto multiple lines when
              // the dialog is narrow, matching AlertDialog's default behavior.
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    child: const Text('Blink'),
                    onPressed: () => widget.onBlink(_hsvColor.toColor(), widget.die, _entityController.text),
                  ),
                  TextButton(
                    child: const Text('Disconnect'),
                    onPressed: () {
                      widget.onDisconnect(widget.die.dieId);
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text('Save'),
                    onPressed: () {
                      widget.onSave(widget.die, _hsvColor.toColor(), _entityController.text, _faceTuple.item2());
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
