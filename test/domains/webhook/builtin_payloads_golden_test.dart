import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:roll_feathers/domains/roll_parser/target_dtos.dart';
import 'package:roll_feathers/domains/webhook/builtin_payloads.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';

// The built-in anchors must reproduce today's output byte-for-byte. The current
// DTOs (built from the same values as PayloadContext.sample) are the oracle.
void main() {
  final ctx = PayloadContext.sample;
  PayloadTemplate byId(String id) => kBuiltinPayloads.firstWhere((p) => p.id == id);

  final ts = DateTime.utc(2026, 7, 6, 21, 15);
  final d1 = DieInfoDTO(id: 'd1', name: 'Gandalf', type: 'd20', value: 18, battery: 87);
  final d2 = DieInfoDTO(id: 'd2', name: 'Shadowfax', type: 'd20', value: 11);
  final dice = [d1, d2];
  final range = RollResultRange(true, 15, 20, true);
  final actions = [ActionDTO(type: 'blink', args: ['green'])];

  test('Discord (Classic) == current DiscordRollDTO', () {
    final dto = DiscordRollDTO(rule: 'attackRoll', aggregate: 18, timestamp: ts, resultDice: dice);
    expect(
      PayloadRenderer.render(byId('discord').body, ctx, PayloadFormat.json),
      jsonEncode(dto.toJson()),
    );
  });

  test('Generic JSON == current RollResultDTO', () {
    final dto = RollResultDTO(
      rule: 'attackRoll',
      aggregate: 18,
      timestamp: ts,
      matchedRange: range,
      allDice: dice,
      resultDice: dice,
      actions: actions,
    );
    expect(
      PayloadRenderer.render(byId('generic').body, ctx, PayloadFormat.json),
      jsonEncode(dto.toJson()),
    );
  });

  test('Generic GET == current rule+aggregate query', () {
    expect(
      PayloadRenderer.render(byId('generic-get').body, ctx, PayloadFormat.form),
      'rule=attackRoll&aggregate=18',
    );
  });

  test('additive Discord built-ins render valid JSON', () {
    for (final id in ['discord-message', 'discord-colored']) {
      expect(() => PayloadRenderer.render(byId(id).body, ctx, PayloadFormat.json), returnsNormally);
    }
  });

  test('reserved names include the built-ins', () {
    expect(kReservedPayloadNames, contains('discord'));
    expect(kReservedPayloadNames, contains('Generic JSON'));
  });
}
