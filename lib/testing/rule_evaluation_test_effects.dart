import 'dart:async';

import 'package:roll_feathers/domains/roll_parser/rule_evaluator.dart';

/// Test-only. Awaits every collected effect to completion so tests can
/// deterministically assert on side-effect spies. Production never awaits
/// effects — it fires them fire-and-forget with per-effect isolation via
/// [RuleEvaluation.fireEffects].
extension RuleEvaluationTestEffects on RuleEvaluation {
  Future<void> runEffects() => Future.wait(effects.map((e) => e()));
}
