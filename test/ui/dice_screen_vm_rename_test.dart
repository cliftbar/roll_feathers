// Integration-style test for the rename wiring: saving a Pixels die's settings
// through DiceScreenViewModel must push the name to the die firmware
// (DieDomain.setDieName), while non-Pixels dice and empty names must not.

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/testing/dsl_test_harness.dart';
import 'package:roll_feathers/ui/die_screen/dice_screen_vm.dart';

import '../test_util.dart';

void main() {
  setupLogger(Level.WARNING);

  late RecordingDieDomain dieDomain;
  late DiceScreenViewModel vm;

  setUp(() async {
    dieDomain = RecordingDieDomain();
    final appService = InMemoryAppService();
    final webhook = WebhookDomain(appService: appService);
    final rp = RuleEvaluator(dieDomain, appService, webhook);
    await rp.init();
    final di = await DiWrapper.forTesting(
      appService: appService,
      dieDomain: dieDomain,
      ruleParser: rp,
      webhookDomain: webhook,
    );
    vm = DiceScreenViewModel(di);
  });

  test('saving a Pixels die name pushes a firmware rename', () async {
    final die = TestBleDie('pixel-A');
    await vm.updateDieSettings.execute(die, DieSettings(friendlyName: 'Sparkle'));
    expect(dieDomain.renamed, contains('pixel-A:Sparkle'));
  });

  test('saving a virtual die name does NOT push a firmware rename', () async {
    final die = VirtualDie(dType: GenericDTypeFactory.getKnownChecked('d20'), name: 'old');
    await vm.updateDieSettings.execute(die, DieSettings(friendlyName: 'NewName'));
    expect(dieDomain.renamed, isEmpty);
  });

  test('empty name does NOT push a firmware rename for a Pixels die', () async {
    final die = TestBleDie('pixel-B');
    await vm.updateDieSettings.execute(die, DieSettings(friendlyName: ''));
    expect(dieDomain.renamed, isEmpty);
  });
}
