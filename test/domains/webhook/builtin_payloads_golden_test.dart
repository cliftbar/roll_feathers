import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';

// The built-in anchors must reproduce today's output byte-for-byte. The expected
// shapes below are exactly what the (now-retired) DiscordRollDTO / RollResultDTO
// produced — built inline so the test is self-contained.
void main() {
  final ctx = PayloadContext.sample;
  PayloadTemplate byId(String id) => kBuiltinPayloads.firstWhere((p) => p.id == id);
  String renderJson(String id) => PayloadRenderer.render(byId(id).body, ctx, PayloadFormat.json);

  const die1 = {'id': 'd1', 'name': 'Gandalf', 'type': 'd20', 'value': 18, 'battery': 87};
  const die2 = {'id': 'd2', 'name': 'Shadowfax', 'type': 'd20', 'value': 11};
  const ts = '2026-07-06T21:15:00.000Z';

  test('Discord (Classic) == the current DiscordRollDTO embed', () {
    final expected = {
      'embeds': [
        {
          'title': 'Rule: attackRoll',
          'timestamp': ts,
          'fields': [
            {'name': 'Aggregate', 'value': '18', 'inline': false},
            {'name': 'Gandalf', 'value': '18 (d20)', 'inline': true},
            {'name': 'Shadowfax', 'value': '11 (d20)', 'inline': true},
          ],
        }
      ],
    };
    expect(renderJson('discord'), jsonEncode(expected));
  });

  test('Generic JSON == the current RollResultDTO', () {
    final expected = {
      'rule': 'attackRoll',
      'timestamp': ts,
      'aggregate': 18,
      'matched_range': {'start': 15, 'end': 20, 'start_inclusive': true, 'end_inclusive': true},
      'result_dice': [die1, die2],
      'all_dice': [die1, die2],
      'actions': [
        {'type': 'blink', 'args': ['green']},
      ],
    };
    expect(renderJson('generic'), jsonEncode(expected));
  });

  test('Generic GET == the current rule+aggregate query', () {
    expect(PayloadRenderer.render(byId('generic-get').body, ctx, PayloadFormat.form), 'rule=attackRoll&aggregate=18');
  });

  test('additive Discord built-ins render valid JSON', () {
    for (final id in ['discord-message', 'discord-colored']) {
      expect(() => renderJson(id), returnsNormally);
    }
  });

  test('reserved names include the built-ins', () {
    expect(kReservedPayloadNames, contains('discord'));
    expect(kReservedPayloadNames, contains('Generic JSON'));
  });
}
