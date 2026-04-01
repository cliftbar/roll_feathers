import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';

class DieListTile extends StatelessWidget {
  const DieListTile({
    super.key,
    required this.die,
    required this.onTap,
    this.themeMode = ThemeMode.system,
  });

  final GenericDie die;
  final VoidCallback onTap;
  final ThemeMode themeMode;

  Color _blinkColor(BuildContext context) =>
      die.blinkColor?.withAlpha(255) ??
      Theme.of(context).textTheme.bodyMedium?.color ??
      (themeMode == ThemeMode.dark ? Colors.white : Colors.black);

  Color _iconColor(BuildContext context) {
    switch (DiceRollState.values[die.state.rollState ?? 0]) {
      case DiceRollState.rolling:
      case DiceRollState.handling:
        return Colors.orange;
      default:
        return _blinkColor(context);
    }
  }

  String get _subtitle {
    final rollState = DiceRollState.values[die.state.rollState ?? DiceRollState.unknown.index];
    final String valueStr;
    switch (rollState) {
      case DiceRollState.rolling:
      case DiceRollState.handling:
        valueStr = ' rolling';
      case DiceRollState.rolled:
      case DiceRollState.onFace:
        valueStr = ' Value: ${die.state.currentFaceValue}';
      default:
        valueStr = '';
    }
    return '${die.dType.name} ${die.state.batteryLevel}%$valueStr ${die.dieId}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      textColor: _blinkColor(context),
      iconColor: _iconColor(context),
      leading: const Icon(Icons.hexagon),
      title: Text(die.friendlyName.isEmpty ? 'Unknown Device ${die.dieId}' : die.friendlyName),
      subtitle: Text(_subtitle),
      onTap: onTap,
    );
  }
}

@Preview(name: 'DieListTile - idle')
Widget dieListTileIdle() => MaterialApp(
      home: Scaffold(
        body: DieListTile(
          die: VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d6'), name: 'Red D6'),
          onTap: () {},
        ),
      ),
    );

@Preview(name: 'DieListTile - rolling')
Widget dieListTileRolling() {
  final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d20'), name: 'Blue D20');
  die.state.rollState = DiceRollState.rolling.index;
  return MaterialApp(
    home: Scaffold(
      body: DieListTile(die: die, onTap: () {}),
    ),
  );
}

@Preview(name: 'DieListTile - rolled with color')
Widget dieListTileRolledWithColor() {
  final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d20'), name: 'Blue D20');
  die.state.rollState = DiceRollState.rolled.index;
  die.state.currentFaceValue = 17;
  die.blinkColor = Colors.blue;
  return MaterialApp(
    home: Scaffold(
      body: DieListTile(die: die, onTap: () {}),
    ),
  );
}
