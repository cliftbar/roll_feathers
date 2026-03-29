import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:roll_feathers/testing/dsl_test_harness.dart' as harness;

void main() {
  test('DSL tester CLI-style runner', () async {
    // Read rule from env: RULE_TEXT or RULE_FILE
    final env = Platform.environment;
    String? rule = env['RULE_TEXT'];
    final ruleFile = env['RULE_FILE'];
    if ((rule == null || rule.isEmpty) && ruleFile != null && ruleFile.isNotEmpty) {
      rule = await File(ruleFile).readAsString();
    }
    // If no rule is provided when running the full test suite, treat this as a no-op.
    if (rule == null || rule.trim().isEmpty) {
      // ignore: avoid_print
      print('DSL CLI runner skipped: Provide RULE_TEXT or RULE_FILE to run this test.');
      return;
    }

    // DICE env: comma-separated specs like d6:6,d8:3,d6:1
    // Optional die id suffix with '#': e.g., d6:6#A1
    final diceEnv = env['DICE'] ?? '';
    if (diceEnv.isEmpty) {
      // ignore: avoid_print
      print('DSL CLI runner skipped: Provide DICE env (e.g., d6:6,d8:3 or d6:6#A1).');
      return;
    }

    final dice = <harness.DieInput>[];
    for (final tok in diceEnv.split(',')) {
      final t = tok.trim();
      if (t.isEmpty) continue;
      final parts = t.split(':');
      if (parts.length < 2) {
        fail('Bad DICE token: $t. Expected dType:faceValue optionally #id');
      }
      final typeAndMaybeId = parts[0];
      final valAndMaybeId = parts[1];

      String dType = typeAndMaybeId;
      String? customId;
      int faceVal;

      // support id after '#'
      if (valAndMaybeId.contains('#')) {
        final pv = valAndMaybeId.split('#');
        faceVal = int.parse(pv[0]);
        customId = pv[1];
      } else {
        faceVal = int.parse(valAndMaybeId);
      }

      dice.add(harness.DieInput(dType, faceVal, id: customId));
    }

    final mod = int.tryParse(env['MODIFIER'] ?? '0') ?? 0;
    final thr = int.tryParse(env['THRESHOLD'] ?? '0') ?? 0;

    final runner = await harness.DslTestRunner.create();
    final res = await runner.run(rule: rule, dice: dice, threshold: thr, modifier: mod);

    // Print a simple report to stdout that tools can parse.
    // Format lines:
    // ACTION <dieId> <action> <colorValue?> [args...]
    for (final a in res.actions) {
      final color = a.colorValue?.toString() ?? '';
      final args = a.args.join(' ');
      // ignore: avoid_print
      print('ACTION ${a.dieId} ${a.action} $color $args'.trim());
    }

    // Also print aggregate and rule name
    // ignore: avoid_print
    print('RESULT ${res.parse.ruleName} ${res.parse.result}');

    // No assertions beyond input validation; this is a runner.
  });
}
