import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

abstract class RollLifecycleObserver {
  /// Called when an individual die enters the rolling state.
  /// Fire-and-forget — errors must be handled internally.
  Future<void> onDieRolling(GenericDie die) async {}

  /// Called once all dice have settled and the roll result is recorded.
  /// Fire-and-forget — errors must be handled internally.
  Future<void> onRollComplete(List<GenericDie> dice, RollResult result) async {}
}
