import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:roll_feathers/domains/roll_parser/target_dtos.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';
import 'package:roll_feathers/util/color.dart';

import '../../helpers/fakes.dart';

void main() {
  PayloadContext build() {
    final die = FakeDie('d1', 'Gandalf', 18, dName: 'd20')..blinkColor = colorMap['green'];
    die.state.batteryLevel = 87;
    return PayloadContext.fromRollData(
      ruleName: 'attackRoll',
      ruleDisplayName: 'Attack Roll',
      rollType: 'max',
      aggregate: 18,
      timestamp: DateTime.utc(2026, 7, 6, 21, 15),
      matchedRange: RollResultRange(true, 15, 20, true),
      allDice: [die],
      resultDiceMap: {die: 18},
      coActions: [ActionDTO(type: 'blink', args: ['green'])],
    );
  }

  String render(String t, PayloadContext c) => PayloadRenderer.render(t, c, PayloadFormat.json);

  test('exposes roll data (die alias, name, value, type)', () {
    final c = build();
    expect(render('{"c":"{{die.name}} rolled {{die.value}} ({{die.type}})"}', c),
        '{"c":"Gandalf rolled 18 (d20)"}');
  });

  test('exposes the reactive blink color from the co-action', () {
    final c = build();
    // colorMap['green'] is pure green → #00FF00 → 65280
    expect(colorToInt(colorMap['green']!), 65280);
    expect(render('{"c":{{blink.colorInt}}}', c), '{"c":65280}');
  });

  test('exposes per-die color', () {
    final c = build();
    expect(render('{"c":{{die.colorInt}}}', c), '{"c":65280}');
  });

  test('unknown blink color falls back to white (matches the blink action)', () {
    final die = FakeDie('d1', 'x', 5, dName: 'd6');
    final c = PayloadContext.fromRollData(
      ruleName: 'r',
      aggregate: 5,
      timestamp: DateTime.utc(2026),
      matchedRange: RollResultRange(true, 1, 6, true),
      allDice: [die],
      resultDiceMap: {die: 5},
      coActions: [ActionDTO(type: 'blink', args: ['notacolor'])],
    );
    expect(render('{"c":{{blink.colorInt}}}', c), '{"c":${colorToInt(colorMap['white']!)}}');
  });

  test('the Discord Message built-in renders from a real roll context', () {
    final c = build();
    final msg = kBuiltinPayloads.firstWhere((p) => p.id == 'discord-message');
    expect(render(msg.body, c), '{"content":"**Gandalf** rolled a **18** on their d20!"}');
  });

  test('battery present → included; null → omitted (Generic JSON)', () {
    final c = build();
    final generic = kBuiltinPayloads.firstWhere((p) => p.id == 'generic');
    final out = render(generic.body, c);
    expect(out, contains('"battery":87'));

    // null battery: a die without a battery reading
    final die = FakeDie('d2', 'NoBat', 5, dName: 'd6')..blinkColor = Colors.blue;
    final c2 = PayloadContext.fromRollData(
      ruleName: 'r',
      aggregate: 5,
      timestamp: DateTime.utc(2026),
      matchedRange: RollResultRange(true, 1, 6, true),
      allDice: [die],
      resultDiceMap: {die: 5},
    );
    expect(render(generic.body, c2), isNot(contains('battery')));
  });
}
