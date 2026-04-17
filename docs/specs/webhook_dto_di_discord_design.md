# Webhook DTO, DI Integration, and Discord Target — Design Spec

> Branch: `cb_webhookTargets`
> Builds on: `docs/specs/dsl_webhook_targets.md` (initial webhook spec)

---

## Problem Statement

Three gaps exist after the initial webhook implementation:

1. **`WebhookDomain` not in DI** — it is constructed inside `RollDomain._()` (roll_domain.dart:64), invisible to `DiWrapper` and untestable in isolation.
2. **Payload built as raw `Map<String, dynamic>` in the parser** — payload structure is scattered inline across both evaluator paths (`_evaluateRuleV11`, `_evaluateRuleV11Async`) with no type safety, no reuse, and different shapes between the two.
3. **No Discord target** — the official Pixels app (pixels-js) supports a `discord` webhook format natively; roll_feathers should too.

---

## Architecture Overview

```
DiWrapper
  └─ WebhookDomain(httpClient)            ← lifted here, exposed as .webhookDomain field
       └─ fireWebhook(url, method, WebhookSerializable)

RollDomain(webhookDomain: ...)            ← injected from DiWrapper
  └─ RuleParser(webhookDomain: ...)       ← passed through

parser.dart: _evaluateRuleV11[Async]
  case webhook  → RollResultPayload.fromRollData(...)  → fireWebhook
  case discord  → DiscordRollPayload(...)              → fireWebhook
```

---

## Interface: `WebhookSerializable`

**Location:** `lib/domains/webhook_domain.dart`

```dart
abstract interface class WebhookSerializable {
  Map<String, dynamic> toJson();
  Map<String, String> toQueryParams();
}
```

**Why in `webhook_domain.dart`, not `result_targets.dart`:** the interface is consumed by `WebhookDomain.fireWebhook()`. Defining it in `result_targets.dart` would force `webhook_domain.dart` to import roll-parser code — backwards dependency. Keeping it in the domain means DTOs import the domain, not vice versa.

`toQueryParams()` serves GET requests. Discord always POSTs but must implement the method; it returns `{'rule': rule}` as a no-op stub.

---

## DTO: `WebhookDieInfo`

**Location:** `lib/domains/roll_parser/result_targets.dart`

Shared serializable snapshot of a single die. Used by both `RollResultPayload` and `DiscordRollPayload`.

```dart
class WebhookDieInfo {
  final String id;
  final String name;
  final String type;
  final int value;
  final int? battery;

  WebhookDieInfo({
    required this.id, required this.name,
    required this.type, required this.value,
    this.battery,
  });

  static WebhookDieInfo fromDie(GenericDie die, int value) => WebhookDieInfo(
    id: die.dieId,
    name: die.friendlyName,
    type: die.dType.name,
    value: value,
    battery: die.state.batteryLevel,
  );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'name': name, 'type': type, 'value': value};
    if (battery != null) m['battery'] = battery;
    return m;
  }
}
```

---

## DTO: `RollResultPayload`

**Location:** `lib/domains/roll_parser/result_targets.dart`

Full roll-result payload for the `webhook` target. Implements `WebhookSerializable`. Has a `fromRollData()` factory because it assembles from many raw sources (dice lists, selection maps, co-actions). Named `RollResultPayload` rather than `WebhookPayload` because future non-roll webhook targets (e.g. die-connect events) would be a different type.

```dart
class RollResultPayload implements WebhookSerializable {
  final String rule;
  final int aggregate;
  final DateTime timestamp;
  final RollResultRange matchedRange;
  final List<WebhookDieInfo> allDice;
  final List<WebhookDieInfo> resultDice;
  final List<Map<String, dynamic>> actions;

  RollResultPayload({
    required this.rule, required this.aggregate, required this.timestamp,
    required this.matchedRange, required this.allDice,
    required this.resultDice, required this.actions,
  });

  static RollResultPayload fromRollData({
    required String ruleName,
    required int aggregate,
    required RollResultRange matchedRange,
    required List<GenericDie> allDice,
    required Map<GenericDie, int> resultDiceMap,
    List<Map<String, dynamic>> coActions = const [],
  }) => RollResultPayload(
    rule: ruleName,
    aggregate: aggregate,
    timestamp: DateTime.now().toUtc(),
    matchedRange: matchedRange,
    allDice: allDice.map((d) => WebhookDieInfo.fromDie(d, d.getFaceValueOrElse())).toList(),
    resultDice: resultDiceMap.entries.map((e) => WebhookDieInfo.fromDie(e.key, e.value)).toList(),
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
    'actions': actions,
  };

  @override
  Map<String, String> toQueryParams() => {
    'rule': rule,
    'aggregate': aggregate.toString(),
  };
}
```

**Sync vs async path:** the async evaluator pre-scans co-actions (other matching action targets in the same `use` block) and passes them as `coActions`. The sync path passes `coActions: []` (the default). Both use the same factory.

---

## DTO: `DiscordRollPayload`

**Location:** `lib/domains/roll_parser/discord_roll_payload.dart` (new file)

Implements `WebhookSerializable`. Produces Discord embed-formatted JSON. **No factory** — the parser's `discord` case constructs it directly with only the four fields it needs.

```dart
class DiscordRollPayload implements WebhookSerializable {
  final String rule;
  final int aggregate;
  final DateTime timestamp;
  final List<WebhookDieInfo> resultDice;

  DiscordRollPayload({
    required this.rule, required this.aggregate,
    required this.timestamp, required this.resultDice,
  });

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
```

**Embed content:** result dice only (the official Pixels app uses a single-die format — title, thumbnail, description — which doesn't translate cleanly to a multi-die rule context).

**Always POST.** Discord webhooks don't support GET; the `discord` parser never writes a method into `args`.

---

## DSL Syntax

```
# Webhook — GET or POST (default POST)
on [5:*] webhook https://example.com/hook
on [5:*] webhook GET https://example.com/hook

# Discord — always POST, always embed format
on [5:*] discord https://discord.com/api/webhooks/123/abc
```

`discord` is a new `ResultTargetType` variant. The `discordP` parser mirrors `webhookP` but strips the optional method prefix — URL is the full rest-of-line, stored in `ResultTargetFunction.action`, `args: []`.

---

## `WebhookDomain` Changes

```dart
// Before
Future<void> fireWebhook({
  required String url,
  required String method,
  required Map<String, dynamic> payload,
  http.Client? httpClient,         // removed — DI supplies the client
})

// After
Future<void> fireWebhook({
  required String url,
  required String method,
  required WebhookSerializable payload,
})
```

- GET: calls `payload.toQueryParams()` to build query params
- POST: calls `jsonEncode(payload.toJson())` as body
- Client lifecycle simplified: `_httpClient ?? http.Client()`; close only if created locally

---

## DI Wiring

```dart
// di.dart — initDi()

// httpClient already existed for HaApiService — reuse it
Client httpClient = http_factory.provideHttpClient();

// New: create WebhookDomain with the shared client
WebhookDomain webhookDomain = WebhookDomain(httpClient: httpClient);

// Updated: inject webhookDomain instead of letting RollDomain create it
RollDomain rollDomain = await RollDomain.create(
  dieDomain, appService, webhookDomain: webhookDomain,
);

return DiWrapper._(..., webhookDomain, ...);
```

`DiWrapper` gains a `final WebhookDomain webhookDomain` field, making it available to any ViewModel that needs it in the future.

---

## `RollDomain` Changes

```dart
// Before
RollDomain._(this._diceDomain, this.appService, {http.Client? httpClient}) {
  webhookDomain = WebhookDomain(httpClient: httpClient);  // internal creation
  ruleParser = RuleParser(_diceDomain, this, appService, webhookDomain, httpClient: httpClient);
}

static Future<RollDomain> create(DieDomain dieDomain, AppService appService,
    {http.Client? httpClient}) async { ... }

// After
RollDomain._(this._diceDomain, this.appService, this.webhookDomain) {
  ruleParser = RuleParser(_diceDomain, this, appService, webhookDomain);
}

static Future<RollDomain> create(DieDomain dieDomain, AppService appService,
    {required WebhookDomain webhookDomain}) async { ... }
```

---

## `RuleParser` Cleanup

`RuleParser` currently stores `_httpClient` (parser.dart:336) and forwards it to `fireWebhook()` as an override parameter. Once `fireWebhook()` drops that parameter, both the `_httpClient` field and the `{http.Client? httpClient}` constructor parameter on `RuleParser` can be removed.

---

## Parser Dispatch

Both sync and async evaluator paths get the same dispatch logic:

```dart
case ResultTargetType.webhook:
  final payload = RollResultPayload.fromRollData(
    ruleName: result.name,
    aggregate: aggValue,
    matchedRange: res.resultRange,
    allDice: rolls,
    resultDiceMap: selMap,
    coActions: coActions,  // [] on sync path, pre-scanned on async path
  );
  _webhookDomain.fireWebhook(
    url: res.targetFunction.action,
    method: res.targetFunction.args.isNotEmpty ? res.targetFunction.args[0] : 'POST',
    payload: payload,
  ).ignore();
  break;

case ResultTargetType.discord:
  final payload = DiscordRollPayload(
    rule: result.name,
    aggregate: aggValue,
    timestamp: DateTime.now().toUtc(),
    resultDice: selMap.keys.map((d) => WebhookDieInfo.fromDie(d, selMap[d]!)).toList(),
  );
  _webhookDomain.fireWebhook(
    url: res.targetFunction.action,
    method: 'POST',
    payload: payload,
  ).ignore();
  break;
```

---

## Alternatives Considered and Rejected

### `WebhookSerializable` in `result_targets.dart`
`webhook_domain.dart` would have to import roll-parser code — backwards dependency. Rejected in favour of defining it where it's consumed.

### Single `WebhookPayload` class for all target types
Rejected. Named `RollResultPayload` to leave room for future non-roll webhook types (die-connect events, etc.) that would have different schemas.

### `DiscordRollPayload.fromRollResultPayload(RollResultPayload)`
Proposed early. Rejected because `DiscordRollPayload` uses only `rule`, `aggregate`, `timestamp`, and `resultDice` — taking a full `RollResultPayload` as input passes in `allDice`, `matchedRange`, and `actions` that Discord never uses. "Why is `DiscordRollPayload` taking all that in if it doesn't use it?"

### `DiscordRollPayload.fromRollData(...)` with same raw inputs as `RollResultPayload`
Would duplicate the `GenericDie → WebhookDieInfo` conversion logic for no benefit. Each handler constructs its own payload inline.

### `WebhookDomain.fireWebhook()` with a `format` flag
Would let the domain switch between JSON and Discord embed formats internally. Rejected — the domain should not know about payload schemas; that's the DTO's responsibility.

### Discord syntax: `discord <url> BotName` (optional username)
Considered. Rejected for now — adds grammar complexity without clear need. Can be added as a later arg.

### Discord embed showing all dice + result dice as separate field groups
Considered. Result dice only chosen first, matching the Pixels app philosophy of surfacing only what triggered the rule.

---

## Implementation Order

| Step | File | Change |
|------|------|--------|
| 1 | `lib/domains/webhook_domain.dart` | Add `WebhookSerializable` interface; update `fireWebhook()` signature |
| 2 | `lib/domains/roll_parser/result_targets.dart` | Add `WebhookDieInfo`, `RollResultPayload`, `discord` enum variant, `discordP` parser |
| 3 | `lib/domains/roll_parser/discord_roll_payload.dart` | New file — `DiscordRollPayload` |
| 4 | `lib/domains/webhook_domain.dart` | Update `fireWebhook()` body (use interface methods, remove `httpClient` param handling) |
| 5 | `lib/domains/roll_parser/parser.dart` | Update webhook + add discord dispatch in both evaluator paths |
| 6 | `lib/domains/roll_parser/parser.dart` | Remove `_httpClient` field and constructor param |
| 7 | `lib/domains/roll_domain.dart` | Accept `WebhookDomain` as required param; remove internal construction |
| 8 | `lib/di/di.dart` | Create `WebhookDomain`; add field; inject into `RollDomain.create()` |
| 9 | `test/domains/roll_parser/dsl_webhook_http_test.dart` | Update to construct `RollResultPayload` instead of raw maps |
| 9 | `test/domains/roll_parser/dsl_discord_http_test.dart` | New test file — Discord embed shape, headers, error handling |
| 10 | `lib/testing/dsl_test_harness.dart` | Pass `webhookDomain` explicitly to `RollDomain.create()` |

---

## Test Coverage

### `dsl_webhook_http_test.dart` (update existing)
- All existing tests updated to construct `RollResultPayload` with a minimal `RollResultRange` and empty dice lists
- Verify JSON body still matches the field structure above
- Verify `toQueryParams()` produces `{rule, aggregate}` on GET path

### `dsl_discord_http_test.dart` (new)
- Verify `Content-Type: application/json` header
- Verify body has top-level `embeds` key
- Verify embed `title` contains rule name
- Verify `fields` array contains an aggregate entry and one entry per result die
- Verify network errors are caught and don't throw

---

## Verification

```
flutter analyze
flutter test test/domains/roll_parser/dsl_webhook_http_test.dart
flutter test test/domains/roll_parser/dsl_discord_http_test.dart
flutter test
```
