import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/dice_sdks/godice.dart';
import 'package:tuple/tuple.dart';

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
  late Color _currentColor;
  late TextEditingController _entityController;
  late Tuple2<Widget, ValueGetter<GenericDType>> _faceTuple;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.die.blinkColor ?? Colors.white;
    _entityController = TextEditingController(text: widget.die.haEntityTargets.firstOrNull ?? '');
    _faceTuple = _makeFaceSelectorWidget(widget.die);
  }

  @override
  void dispose() {
    _entityController.dispose();
    super.dispose();
  }

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
            const Text('Pick a color'),
            ColorPicker(
              pickerColor: _currentColor,
              hexInputBar: true,
              paletteType: PaletteType.hueWheel,
              onColorChanged: (Color color) {
                _currentColor = color;
              },
              pickerAreaHeightPercent: 0.8,
            ),
            const SizedBox(height: 16),
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
          onPressed: () => widget.onBlink(_currentColor, widget.die, _entityController.text),
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
            widget.onSave(widget.die, _currentColor, _entityController.text, _faceTuple.item2());
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
