/// The data a [PayloadTemplate] renders against: roll data + rule outputs, as a
/// plain nested map the renderer walks by dotted path. Phase 2 adds
/// `PayloadContext.fromEvaluation(...)`; this file provides the structure and the
/// canned sample used by the live preview and the render tests.
class PayloadContext {
  /// Root map: scalars, nested maps, and lists (`resultDice`/`allDice`/`actions`).
  final Map<String, dynamic> root;

  const PayloadContext(this.root);

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
