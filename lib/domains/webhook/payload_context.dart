import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:roll_feathers/domains/roll_parser/target_dtos.dart';
import 'package:roll_feathers/util/color.dart';

/// The data a [PayloadTemplate] renders against: roll data + rule outputs, as a
/// plain nested map the renderer walks by dotted path. Built from a roll
/// evaluation via [PayloadContext.fromRollData]; a canned [sample] backs the
/// editor preview and the render/golden tests.
class PayloadContext {
  /// Root map: scalars, nested maps, and lists (`resultDice`/`allDice`/`actions`).
  final Map<String, dynamic> root;

  const PayloadContext(this.root);

  /// Assembles the render context from a matched roll result. Exposes the same
  /// roll data the old DTOs collected, plus **rule outputs**: the reactive
  /// `blink` (from the co-actions in this result block), `actions`, and
  /// `threshold`/`modifier`.
  factory PayloadContext.fromRollData({
    required String ruleName,
    String? ruleDisplayName,
    String rollType = 'normal',
    required int aggregate,
    required DateTime timestamp,
    required RollResultRange matchedRange,
    required List<GenericDie> allDice,
    required Map<GenericDie, int> resultDiceMap,
    int? threshold,
    int? modifier,
    List<ActionDTO> coActions = const [],
  }) {
    return PayloadContext({
      'rule': {'name': ruleName, 'displayName': ruleDisplayName ?? ruleName, 'id': ruleName},
      'rollType': rollType,
      'aggregate': aggregate,
      'timestamp': timestamp.toIso8601String(),
      'matched': {
        'start': matchedRange.start,
        'end': matchedRange.end,
        'startInclusive': matchedRange.startInclusive,
        'endInclusive': matchedRange.endInclusive,
      },
      'resultDice': resultDiceMap.entries.map((e) => _dieMap(e.key, e.value)).toList(),
      'allDice': allDice.map((d) => _dieMap(d, d.getFaceValueOrElse())).toList(),
      'threshold': threshold,
      'modifier': modifier,
      'blink': _blinkFrom(coActions),
      'actions': coActions.map((a) => {'type': a.type, 'args': a.args}).toList(),
    });
  }

  static Map<String, dynamic> _dieMap(GenericDie die, int value) {
    final c = die.blinkColor;
    return {
      'id': die.dieId,
      'name': die.friendlyName,
      'type': die.dType.name,
      'value': value,
      'battery': die.state.batteryLevel,
      'color': c == null ? null : colorToHex(c),
      'colorInt': c == null ? null : colorToInt(c),
    };
  }

  /// The reactive blink for this result block: the first `blink` co-action's
  /// color (resolved via the shared color map) as hex + int, plus any style arg.
  static Map<String, dynamic>? _blinkFrom(List<ActionDTO> coActions) {
    for (final a in coActions) {
      if (a.type == 'blink' && a.args.isNotEmpty) {
        final col = colorMap[a.args.first.toLowerCase()];
        if (col == null) return null;
        return {
          'color': colorToHex(col),
          'colorInt': colorToInt(col),
          'style': a.args.length > 1 ? a.args[1] : null,
        };
      }
    }
    return null;
  }

  /// A fixed multi-die fixture engineered to exercise every case (mixed dice,
  /// a null battery, a display name, a `max` roll with a reactive blink). Shared
  /// by the editor preview and the renderer/golden tests so they can't disagree.
  static PayloadContext get sample => PayloadContext({
        'rule': {'name': 'attackRoll', 'displayName': 'Attack Roll', 'id': 'rule-1'},
        'rollType': 'max',
        'aggregate': 18,
        'timestamp': DateTime.utc(2026, 7, 6, 21, 15).toIso8601String(),
        'matched': {'start': 15, 'end': 20, 'startInclusive': true, 'endInclusive': true},
        'resultDice': [_gandalf, _shadowfax],
        'allDice': [_gandalf, _shadowfax],
        'threshold': null,
        'modifier': null,
        'blink': {'color': '#00FF00', 'colorInt': 65280, 'style': null},
        'actions': [
          {'type': 'blink', 'args': ['green']},
        ],
      });

  static Map<String, dynamic> get _gandalf => {
        'id': 'd1',
        'name': 'Gandalf',
        'type': 'd20',
        'value': 18,
        'battery': 87,
        'color': '#5865F2',
        'colorInt': 5793266,
      };

  static Map<String, dynamic> get _shadowfax => {
        'id': 'd2',
        'name': 'Shadowfax',
        'type': 'd20',
        'value': 11,
        'battery': null, // exercises conditional / null handling
        'color': '#2ECC71',
        'colorInt': 3066993,
      };
}
