import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';

class DieListTile extends StatefulWidget {
  const DieListTile({
    super.key,
    required this.die,
    required this.onTap,
    this.themeMode = ThemeMode.system,
  });

  final GenericDie die;
  final VoidCallback onTap;
  final ThemeMode themeMode;

  @override
  State<DieListTile> createState() => _DieListTileState();
}

class _DieListTileState extends State<DieListTile> with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (_isRolling) _spinController.repeat();
  }

  @override
  void didUpdateWidget(DieListTile old) {
    super.didUpdateWidget(old);
    if (_isRolling && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!_isRolling && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  bool get _isRolling {
    final state = DiceRollState.values[widget.die.state.rollState ?? 0];
    return state == DiceRollState.rolling || state == DiceRollState.handling;
  }

  Color _blinkColor(BuildContext context) =>
      widget.die.blinkColor?.withAlpha(255) ??
      Theme.of(context).textTheme.bodyMedium?.color ??
      (widget.themeMode == ThemeMode.dark ? Colors.white : Colors.black);

  String get _subtitle {
    final rollState = DiceRollState.values[widget.die.state.rollState ?? DiceRollState.unknown.index];
    final String valueStr;
    switch (rollState) {
      case DiceRollState.rolling:
      case DiceRollState.handling:
        valueStr = ' rolling';
      case DiceRollState.rolled:
      case DiceRollState.onFace:
        valueStr = ' Value: ${widget.die.state.currentFaceValue}';
      default:
        valueStr = '';
    }
    return '${widget.die.dType.name} ${widget.die.state.batteryLevel}%$valueStr ${widget.die.dieId}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _blinkColor(context);
    final faces = widget.die.dType.faces;

    final Widget dieIcon = _DieIcon(faces: faces, color: color);

    final Widget leading = _isRolling
        ? RotationTransition(turns: _spinController, child: dieIcon)
        : dieIcon;

    return ListTile(
      textColor: color,
      leading: leading,
      title: Text(widget.die.friendlyName.isEmpty ? 'Unknown Device ${widget.die.dieId}' : widget.die.friendlyName),
      subtitle: Text(_subtitle),
      onTap: widget.onTap,
    );
  }
}

// ── Die shape icon ─────────────────────────────────────────────────────────────

class _DieIcon extends StatelessWidget {
  const _DieIcon({required this.faces, required this.color});

  final int faces;
  final Color color;

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(_size, _size),
      painter: _DieIconPainter(faces: faces, color: color),
    );
  }
}

class _DieIconPainter extends CustomPainter {
  final int faces;
  final Color color;

  const _DieIconPainter({required this.faces, required this.color});

  Path _polygonPath(Offset center, double radius, int sides, double startAngle) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = startAngle + (2 * pi * i / sides);
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  void _drawText(Canvas canvas, Offset center, String text, Color textColor, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  Color _contrastColor(Color bg) =>
      bg.computeLuminance() > 0.4 ? Colors.black : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final fillPaint = Paint()..color = color..style = PaintingStyle.fill;

    switch (faces) {
      case 4:
        // d4: upward triangle
        canvas.drawPath(_polygonPath(center, r * 0.85, 3, -pi / 2), fillPaint);

      case 6:
        // d6: diamond (square rotated 45°)
        canvas.drawPath(_polygonPath(center, r * 0.90, 4, pi / 4), fillPaint);

      case 8:
        // d8-B: diamond (cardinal vertices) + horizontal equator line
        canvas.drawPath(_polygonPath(center, r * 0.90, 4, -pi / 2), fillPaint);
        canvas.drawLine(
          Offset(center.dx - r * 0.90, center.dy),
          Offset(center.dx + r * 0.90, center.dy),
          Paint()
            ..color = _contrastColor(color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * 0.10,
        );

      case 10:
        // d10-A: filled pentagon + pentagram (connect each vertex to vertex+2)
        canvas.drawPath(_polygonPath(center, r * 0.90, 5, -pi / 2), fillPaint);
        final pentR = r * 0.90;
        final starVerts = List.generate(5, (i) => Offset(
          center.dx + pentR * cos(-pi / 2 + 2 * pi * i / 5),
          center.dy + pentR * sin(-pi / 2 + 2 * pi * i / 5),
        ));
        final starPaint = Paint()
          ..color = _contrastColor(color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.08;
        for (int i = 0; i < 5; i++) {
          canvas.drawLine(starVerts[i], starVerts[(i + 2) % 5], starPaint);
        }

      case 12:
        // d12: filled dodecagon + inner pentagon outline (dodecahedron face)
        canvas.drawPath(_polygonPath(center, r * 0.90, 12, 0), fillPaint);
        canvas.drawPath(
          _polygonPath(center, r * 0.60, 5, -pi / 2),
          Paint()
            ..color = _contrastColor(color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * 0.09,
        );

      case 20:
        // d20: filled hexagon + inner triangle outline (icosahedron face)
        canvas.drawPath(_polygonPath(center, r * 0.90, 6, 0), fillPaint);
        canvas.drawPath(
          _polygonPath(center, r * 0.65, 3, -pi / 2),
          Paint()
            ..color = _contrastColor(color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * 0.09,
        );

      default:
        // Custom / unknown: square with face count number
        canvas.drawPath(_polygonPath(center, r * 0.90, 4, 0), fillPaint);
        final label = faces <= 0 ? '?' : '$faces';
        _drawText(canvas, center, label, _contrastColor(color), size.width * 0.38);
    }
  }

  @override
  bool shouldRepaint(_DieIconPainter old) => old.faces != faces || old.color != color;
}

// ── Previews ───────────────────────────────────────────────────────────────────

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

@Preview(name: 'DieListTile - all die types')
Widget dieListTileAllTypes() {
  final types = ['d4', 'd6', 'd8', 'd10', 'd12', 'd20'];
  final colors = [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple];
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          for (int i = 0; i < types.length; i++)
            DieListTile(
              die: VirtualDie(dType: GenericDTypeFactory.getKnownChecked(types[i]), name: types[i])
                ..blinkColor = colors[i],
              onTap: () {},
            ),
          // Custom face count
          DieListTile(
            die: VirtualDie(
              dType: GenericDType('d7', 7, 7, 1, 1),
              name: 'Custom d7',
            )..blinkColor = Colors.teal,
            onTap: () {},
          ),
        ],
      ),
    ),
  );
}
