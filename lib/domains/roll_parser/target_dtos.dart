import 'package:roll_feathers/util/json_serializable.dart';

/// A co-action fired in a result block (e.g. `blink green`). Surfaced to webhook
/// payload templates as `{{actions}}` / `{{blink.*}}`.
///
/// The old roll/discord payload DTOs (RollResultDTO, DiscordRollDTO, DieInfoDTO)
/// were retired: payloads are now template-driven — the "Generic JSON" and
/// "Discord (Classic)" built-in templates reproduce that output byte-for-byte.
class ActionDTO implements JsonSerializable {
  final String type;
  final List<String> args;

  ActionDTO({required this.type, required this.args});

  @override
  Map<String, dynamic> toJson() => {'type': type, 'args': args};
}
