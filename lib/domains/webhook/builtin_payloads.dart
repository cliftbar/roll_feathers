import 'package:roll_feathers/domains/webhook/payload_template.dart';

/// Built-in payload templates — ordinary library entries, not hardcoded paths.
/// "discord", "generic", and "generic-get" reproduce today's output byte-for-byte
/// (golden-tested); the others are additive. Names are reserved (user payloads
/// can't shadow them).
const List<PayloadTemplate> kBuiltinPayloads = [
  // ── Discord (Classic) ── byte-for-byte the current DiscordRollDTO ────────────
  PayloadTemplate(
    id: 'discord',
    name: 'Discord (Classic)',
    category: 'discord',
    isBuiltin: true,
    body: '{"embeds":[{"title":"Rule: {{rule.name}}","timestamp":"{{timestamp}}","fields":['
        '{"name":"Aggregate","value":"{{aggregate}}","inline":false}'
        '{{#resultDice}},{"name":"{{die.name}}","value":"{{die.value}} ({{die.type}})","inline":true}{{/resultDice}}'
        ']}]}',
  ),

  // ── Discord Message ── the friendly one-liner most people want ───────────────
  PayloadTemplate(
    id: 'discord-message',
    name: 'Discord Message',
    category: 'discord',
    isBuiltin: true,
    body: '{"content":"**{{die.name}}** rolled a **{{die.value}}** on their {{die.type}}!"}',
  ),

  // ── Discord Colored ── one embed per die, tinted by die color ────────────────
  PayloadTemplate(
    id: 'discord-colored',
    name: 'Discord Colored',
    category: 'discord',
    isBuiltin: true,
    body: '{"embeds":[{{#resultDice}}'
        '{"title":"{{die.name}}","description":"rolled {{die.value}} on {{die.type}}"'
        '{{?die.colorInt}},"color":{{die.colorInt}}{{/?}}},'
        '{{/resultDice}}]}',
  ),

  // ── Generic JSON ── byte-for-byte the current RollResultDTO ──────────────────
  PayloadTemplate(
    id: 'generic',
    name: 'Generic JSON',
    category: 'generic',
    isBuiltin: true,
    body: '{"rule":"{{rule.name}}","timestamp":"{{timestamp}}","aggregate":{{aggregate}},'
        '"matched_range":{"start":{{matched.start}},"end":{{matched.end}},'
        '"start_inclusive":{{matched.startInclusive}},"end_inclusive":{{matched.endInclusive}}},'
        '"result_dice":[{{#resultDice}}{"id":"{{die.id}}","name":"{{die.name}}","type":"{{die.type}}","value":{{die.value}}'
        '{{?die.battery}},"battery":{{die.battery}}{{/?}}},{{/resultDice}}],'
        '"all_dice":[{{#allDice}}{"id":"{{die.id}}","name":"{{die.name}}","type":"{{die.type}}","value":{{die.value}}'
        '{{?die.battery}},"battery":{{die.battery}}{{/?}}},{{/allDice}}],'
        '"actions":{{actions.json}}}',
  ),

  // ── Generic GET ── the current rule+aggregate query ──────────────────────────
  PayloadTemplate(
    id: 'generic-get',
    name: 'Generic GET',
    category: 'generic',
    isBuiltin: true,
    method: 'GET',
    format: PayloadFormat.form,
    body: 'rule={{rule.name}}&aggregate={{aggregate}}',
  ),
];

/// Reserved built-in names/ids (user payloads may not collide).
final Set<String> kReservedPayloadNames = {
  for (final p in kBuiltinPayloads) ...{p.id, p.name},
};
