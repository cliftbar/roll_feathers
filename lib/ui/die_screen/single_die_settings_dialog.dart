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
  late HSVColor _hsvColor;
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
        );
      case _ColorMode.rgbSliders:
        return Column(
          children: [
            ColorPickerSlider(TrackType.red, _hsvColor, _onHsvColorChanged, displayThumbColor: true),
            const SizedBox(height: 8),
            ColorPickerSlider(TrackType.green, _hsvColor, _onHsvColorChanged, displayThumbColor: true),
            const SizedBox(height: 8),
            ColorPickerSlider(TrackType.blue, _hsvColor, _onHsvColorChanged, displayThumbColor: true),
          ],
        );
    }
  }

  Widget _buildNumericInputs() {
    switch (_colorMode) {
      case _ColorMode.hexWheel:
        return _inputRow([
          _field(
            label: '#',
            controller: _hexCtrl,
            focusNode: _hexFocus,
            onChanged: _onHexFieldChanged,
            width: 90,
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
              isDense: true,
            ),
            inputFormatters: formatters,
            keyboardType: TextInputType.number,
          ),
        ),
      );

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
    return AlertDialog(
      title: Text('${widget.die.friendlyName} Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Face Count'),
            _faceTuple.item1,
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Color'),
                DropdownButton<_ColorMode>(
                  value: _colorMode,
                  onChanged: (mode) {
                    if (mode != null) setState(() => _colorMode = mode);
                  },
                  items: _ColorMode.values
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
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
      actions: [
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
