# Open Issues & TODOs

## Webhook / Discord Targets

### Discord embed format
The current `DiscordRollDTO.toJson()` produces a generic embed with a title, color, and fields
(Aggregate + one field per die). The official Pixels Companion app uses a specific embed schema for
dice rolls. We should verify whether that format is published and align with it if possible.

**Tracking:** `lib/domains/roll_parser/target_dtos.dart` — `DiscordRollDTO.toJson()`

### Test helper consolidation
`_Recorder` (MockClient + request/body capture) is duplicated across
`dsl_webhook_evaluation_test.dart` and `dsl_discord_evaluation_test.dart`. Extract to
`test/helpers/`.

`DslTestRunner` in `dsl_test_harness.dart` constructs `WebhookDomain()` with no mock client, so
any rule containing a live webhook target would hit the network in tests. Pass a mock or no-op
client via an optional parameter.

## Code Quality

### Silent PackageInfo error suppression
`di.dart` catches all errors from `PackageInfo.fromPlatform()` with `catch (_)` and no logging.
Add at least a `debugPrint` so failures on unexpected platforms are diagnosable.

**File:** `lib/di/di.dart`

### URL parse errors indistinguishable from HTTP errors
`WebhookDomain.fireWebhook` catches `FormatException` from `Uri.parse(url)` in the same `catch (e)`
block as network errors, producing the same warning log. Consider catching `FormatException`
separately with a more specific message.

**File:** `lib/domains/webhook_domain.dart`

### GET webhook payload is sparse
`RollResultDTO.toQueryParams()` only sends `rule` and `aggregate`. A consumer expecting dice detail
over GET would need to use POST. This trade-off should be documented in the DSL spec or a comment.

**File:** `lib/domains/roll_parser/target_dtos.dart`

### No test for malformed webhook URL
`WebhookDomain.fireWebhook` handles `Uri.parse` exceptions gracefully but there is no test
confirming the warning log fires and no exception propagates to the caller.

**File:** `test/domains/roll_parser/dsl_webhook_http_test.dart` (add a case)

## Architecture

### Separate parse and evaluate steps in RuleEvaluator
`RuleEvaluator` currently handles both DSL parsing (`v11ScriptParser`, `getParsedScript`) and
runtime evaluation (`_evaluateRuleV11`). These are distinct responsibilities. Consider splitting
into a `RuleParser` (pure parse → `ParsedScriptV11`) and a `RuleEvaluator` (takes a parsed script
+ runtime context → `ParseResult`). This would make unit-testing the parse step in isolation
straightforward and decouple the two phases.

**Affected files:** `lib/domains/roll_parser/rule_evaluator.dart`

## iOS

### ATS (App Transport Security)
`NSAllowsArbitraryLoads: true` should be added to `ios/Runner/Info.plist` so that user-configured
webhook URLs over plain HTTP are not blocked by iOS ATS. This has not been done yet.

**File:** `ios/Runner/Info.plist`
