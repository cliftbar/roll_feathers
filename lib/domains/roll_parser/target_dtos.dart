import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/roll_parser/result_targets.dart';
import 'package:roll_feathers/domains/webhook_domain.dart';
import 'package:roll_feathers/util/json_serializable.dart';

class DieInfoDTO implements JsonSerializable {
  final String id;
  final String name;
  final String type;
  final int value;
  final int? battery;

  DieInfoDTO({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    this.battery,
  });

  static DieInfoDTO fromDie(GenericDie die, int value) => DieInfoDTO(
        id: die.dieId,
        name: die.friendlyName,
        type: die.dType.name,
        value: value,
        battery: die.state.batteryLevel,
      );

  @override
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'name': name, 'type': type, 'value': value};
    if (battery != null) m['battery'] = battery;
    return m;
  }
}

class ActionDTO implements JsonSerializable {
  final String type;
  final List<String> args;

  ActionDTO({required this.type, required this.args});

  @override
  Map<String, dynamic> toJson() => {'type': type, 'args': args};
}

class RollResultDTO implements WebhookPayload {
  final String rule;
  final int aggregate;
  final DateTime timestamp;
  final RollResultRange matchedRange;
  final List<DieInfoDTO> allDice;
  final List<DieInfoDTO> resultDice;
  final List<ActionDTO> actions;

  RollResultDTO({
    required this.rule,
    required this.aggregate,
    required this.timestamp,
    required this.matchedRange,
    required this.allDice,
    required this.resultDice,
    required this.actions,
  });

  static RollResultDTO fromRollData({
    required String ruleName,
    required int aggregate,
    required DateTime timestamp,
    required RollResultRange matchedRange,
    required List<GenericDie> allDice,
    required Map<GenericDie, int> resultDiceMap,
    List<ActionDTO> coActions = const [],
  }) =>
      RollResultDTO(
        rule: ruleName,
        aggregate: aggregate,
        timestamp: timestamp,
        matchedRange: matchedRange,
        allDice: allDice.map((d) => DieInfoDTO.fromDie(d, d.getFaceValueOrElse())).toList(),
        resultDice: resultDiceMap.entries.map((e) => DieInfoDTO.fromDie(e.key, e.value)).toList(),
        actions: coActions,
      );

  @override
  Map<String, dynamic> toJson() => {
        'rule': rule,
        'timestamp': timestamp.toIso8601String(),
        'aggregate': aggregate,
        'matched_range': {
          'start': matchedRange.start,
          'end': matchedRange.end,
          'start_inclusive': matchedRange.startInclusive,
          'end_inclusive': matchedRange.endInclusive,
        },
        'result_dice': resultDice.map((d) => d.toJson()).toList(),
        'all_dice': allDice.map((d) => d.toJson()).toList(),
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  @override
  Map<String, String> toQueryParams() => {
        'rule': rule,
        'aggregate': aggregate.toString(),
      };
}

class DiscordRollDTO implements WebhookPayload {
  final String rule;
  final int aggregate;
  final DateTime timestamp;
  final List<DieInfoDTO> resultDice;

  DiscordRollDTO({
    required this.rule,
    required this.aggregate,
    required this.timestamp,
    required this.resultDice,
  });

  static DiscordRollDTO fromRollData({
    required String ruleName,
    required int aggregate,
    required DateTime timestamp,
    required Map<GenericDie, int> resultDiceMap,
  }) =>
      DiscordRollDTO(
        rule: ruleName,
        aggregate: aggregate,
        timestamp: timestamp,
        resultDice: resultDiceMap.entries.map((e) => DieInfoDTO.fromDie(e.key, e.value)).toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
        'embeds': [
          {
            'title': 'Rule: $rule',
            'timestamp': timestamp.toIso8601String(),
            'fields': [
              {'name': 'Aggregate', 'value': '$aggregate', 'inline': false},
              ...resultDice.map((d) => {
                    'name': d.name,
                    'value': '${d.value} (${d.type})',
                    'inline': true,
                  }),
            ],
          }
        ],
      };

  @override
  Map<String, String> toQueryParams() => {'rule': rule};
}
