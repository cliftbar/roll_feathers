# Open Issues & TODOs

## Webhook / Discord Targets

### Test helper consolidation
`_Recorder` (MockClient + request/body capture) is duplicated across
`dsl_webhook_evaluation_test.dart` and `dsl_discord_evaluation_test.dart`. Extract to
`test/helpers/`.

`DslTestRunner` in `dsl_test_harness.dart` constructs `WebhookDomain()` with no mock client, so
any rule containing a live webhook target would hit the network in tests. Pass a mock or no-op
client via an optional parameter.

## Code Quality

### No test for malformed webhook URL
`WebhookDomain.fireWebhook` handles `Uri.parse` exceptions gracefully but there is no test
confirming the warning log fires and no exception propagates to the caller.

**File:** `test/domains/roll_parser/dsl_webhook_http_test.dart` (add a case)

