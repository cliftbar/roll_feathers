# Webhook Test Spec

## Overview

Full test coverage for the `webhook` DSL target, covering:

- **Parsing** — DSL grammar recognises `webhook [GET|POST] <url>` correctly
- **`fireWebhook` function** — HTTP dispatch with correct headers, body, and query params
- **Evaluator dispatch** — async and sync paths fire at the right time with the right payload
- **Integration** — real HTTP server verifies end-to-end delivery

---

## Prerequisite: injectable HTTP client

`fireWebhook` currently calls the global `http.get`/`http.post` helpers, which cannot be
intercepted in tests. Three small changes make the function injectable without altering the
public API for production callers:

### `lib/domains/roll_parser/result_targets.dart`

Add optional `http.Client? httpClient` to `fireWebhook`. When `null` (production), create and
close a per-call `http.Client()`. When provided (tests), use it as-is.

```dart
Future<void> fireWebhook({
  required String url,
  required String method,
  required Map<String, dynamic> payload,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  try {
    ...
  } catch (e) { ... }
  finally {
    if (httpClient == null) client.close();
  }
}
```

### `lib/domains/roll_parser/parser.dart`

Add `final http.Client? _httpClient` field and optional named constructor parameter
`{http.Client? httpClient}`. Pass `httpClient: _httpClient` to both `fireWebhook` call sites
(sync v1.1 path and async path).

### `lib/domains/roll_domain.dart`

Add `{http.Client? httpClient}` to `RollDomain.create()` and thread through
`RollDomain._()` → `RuleParser(...)`.

---

## Test files

```
test/domains/roll_parser/
  dsl_webhook_parsing_test.dart     # pure grammar, no HTTP
  dsl_webhook_http_test.dart        # fireWebhook with MockClient
  dsl_webhook_evaluation_test.dart  # evaluator dispatch with captured requests
  dsl_webhook_integration_test.dart # dart:io HttpServer end-to-end
```

---

## Suite 1 — DSL parsing  (`dsl_webhook_parsing_test.dart`)

No network. Uses `RuleParser.v11ScriptParser` and the `resultTarget` parser directly.

| # | Test name | Input / setup | Expected |
|---|-----------|---------------|----------|
| 1.1 | explicit POST parses method and URL | `"webhook POST https://example.com/roll"` | `rtType=webhook`, `action="https://example.com/roll"`, `args[0]="POST"` |
| 1.2 | explicit GET parses method and URL | `"webhook GET https://example.com/roll"` | `args[0]="GET"`, `action=url` |
| 1.3 | omitted method defaults to POST | `"webhook https://example.com/roll"` | `args[0]="POST"` |
| 1.4 | method keyword is case-insensitive (lowercase get) | `"webhook get https://example.com"` | `args[0]="GET"` |
| 1.5 | method keyword is case-insensitive (lowercase post) | `"webhook post https://example.com"` | `args[0]="POST"` |
| 1.6 | URL with path segments preserved | `"webhook POST https://example.com/a/b/c"` | `action="https://example.com/a/b/c"` |
| 1.7 | URL with query string preserved | `"webhook POST https://example.com/hook?foo=bar"` | `action="https://example.com/hook?foo=bar"` |
| 1.8 | unknown method prefix treated as part of URL | `"webhook DELETE https://example.com"` | `args[0]="POST"`, `action="DELETE https://example.com"` |
| 1.9 | webhook in full v11 script with POST | script with `on result [*:*] webhook POST https://example.com` | parses successfully, target type is `webhook`, method=POST |
| 1.10 | webhook in full v11 script with GET | script with `on result [5:15] webhook GET https://example.com` | parses successfully, method=GET, range [5:15] |
| 1.11 | `ResultTargetType.byKey('webhook')` resolves | `ResultTargetType.byKey('webhook')` | equals `ResultTargetType.webhook` |
| 1.12 | webhook coexists with action target in same block | script with blink AND webhook on same range | both targets in `block.targets`, types are `action` and `webhook` |

---

## Suite 2 — `fireWebhook` function  (`dsl_webhook_http_test.dart`)

Uses `package:http/testing.dart` `MockClient` to intercept requests.

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 2.1 | POST sends request to correct URL | `fireWebhook(url: "http://localhost/roll", method: "POST", payload: {...})` | captured request URL == `http://localhost/roll` |
| 2.2 | POST sets Content-Type: application/json | same | `Content-Type` header == `"application/json"` |
| 2.3 | POST body decodes to provided payload | payload `{"rule": "test", "aggregate": 7}` | `jsonDecode(body)` == payload map |
| 2.4 | GET uses correct URL | `fireWebhook(url: "http://localhost/hook", method: "GET", payload: {"aggregate": 7, "rule": "test"})` | request URL starts with `http://localhost/hook` |
| 2.5 | GET appends aggregate query param | same | URL query contains `aggregate=7` |
| 2.6 | GET appends rule query param | same | URL query contains `rule=test` |
| 2.7 | GET sends no body | same | request body is empty |
| 2.8 | HTTP error does not throw | `MockClient` throws `Exception` | `fireWebhook` returns normally |
| 2.9 | malformed URL does not throw | `url: "not a url"` | `fireWebhook` returns normally |
| 2.10 | injected client is used | MockClient that records `wasCalled = true` | `wasCalled` is true after call |
| 2.11 | GET replaces all query params on URL | URL already has `?foo=bar`, GET fired | only `aggregate` and `rule` appear in final URL (not `foo`) |

Note on 2.11: `Uri.replace(queryParameters: {...})` replaces — not merges — existing params. Test documents this behavior.

---

## Suite 3 — Evaluator dispatch  (`dsl_webhook_evaluation_test.dart`)

Uses `MockClient` injected through `RollDomain.create(..., httpClient: mockClient)`.

### 3a — Async path (`runRuleAsync`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 3.1 | POST fires when range matches | dice sum=10, range `[*:*]`, POST webhook | MockClient receives one POST request |
| 3.2 | POST does not fire when range does not match | dice sum=5, range `[10:20]` | MockClient receives zero requests |
| 3.3 | payload contains `rule` field | POST webhook | `body['rule'] == ruleName` |
| 3.4 | payload contains `aggregate` field | dice sum=10 | `body['aggregate'] == 10` |
| 3.5 | payload contains valid ISO-8601 `timestamp` | POST webhook | `DateTime.parse(body['timestamp'])` succeeds, isUtc == true |
| 3.6 | payload contains `matched_range` with correct bounds | range `[5:15]` | `body['matched_range'] == {start: 5, end: 15, start_inclusive: true, end_inclusive: true}` |
| 3.7 | exclusive range bounds stored as raw (pre-adjustment) values | range `(5:15)` | `body['matched_range']['start'] == 5`, `start_inclusive == false` |
| 3.8 | `result_dice` contains selection dice | selection = top 1 die from 3 dice | `result_dice.length == 1`, die id matches highest die |
| 3.9 | `all_dice` contains all rolled dice | 3 dice rolled | `all_dice.length == 3` |
| 3.10 | die object has id, name, type, value | FakeDie with known fields | die JSON matches expected fields |
| 3.11 | battery included in die object when available | `die.state.batteryLevel = 80` | `die['battery'] == 80` in both result_dice and all_dice |
| 3.12 | battery omitted from die object when null | `die.state.batteryLevel == null` | `die` map does not contain key `'battery'` |
| 3.13 | `actions` contains co-action blink | blink blue + webhook in same block, both match | `body['actions'] == [{'type': 'blink', 'args': ['blue']}]` |
| 3.14 | `actions` excludes other webhook targets | two webhooks in same block | neither webhook appears in `actions` |
| 3.15 | `actions` strips `$ALL_DICE` token from args | `action blink $ALL_DICE` + webhook | `actions[0]['args']` does not contain `'$ALL_DICE'` |
| 3.16 | GET fires with aggregate and rule query params | GET webhook, dice sum=7 | request URL contains `aggregate=7&rule=<ruleName>` |
| 3.17 | webhook failure does not prevent co-action blink | MockClient throws, blink in same block | `dd.blinked` is non-empty despite HTTP error |
| 3.18 | multiple webhooks in same block all fire | two webhook targets, same matching range | MockClient receives two requests |

### 3b — Sync path (`runRule`)

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 3.19 | sync path: POST fires (fire-and-forget) | `parser.runRule(script, rolls)` | MockClient receives one POST (after awaiting settlement) |
| 3.20 | sync path: minimal payload has `rule` and `aggregate` only | POST in sync path | body contains `rule` and `aggregate`; no `timestamp`, `result_dice`, `all_dice`, `actions` |

---

## Suite 4 — Integration  (`dsl_webhook_integration_test.dart`)

Uses `dart:io` `HttpServer` bound to `localhost:0` (OS-assigned port).

| # | Test name | Setup | Expected |
|---|-----------|-------|----------|
| 4.1 | POST reaches real server | full DSL parse + `runRuleAsync` → HTTP server | server receives one request |
| 4.2 | POST body is valid JSON | same | `jsonDecode(body)` succeeds, contains `rule` and `aggregate` |
| 4.3 | GET reaches real server | GET webhook variant | server receives one GET request with expected query params |
| 4.4 | dice not interrupted when server returns 500 | server always returns 500 | `runRuleAsync` completes normally, no exception |
| 4.5 | dice not interrupted when server is unreachable | server closed before request fires | `runRuleAsync` completes normally |

---

## Notes

- `FakeDie.state` is already a public mutable field; tests can set `die.state = DiceState(currentFaceValue: v, batteryLevel: 80)` to inject battery data.
- `MockClient` is from `package:http/testing.dart` (ships with `http: ^1.4.0`; no new dependency needed).
- `dart:io` `HttpServer` requires the test process to have network access; tests should bind to `InternetAddress.loopbackIPv4` and always close the server in a `tearDown`.
- Suite 4 tests are inherently slower (real I/O); mark the group with a comment rather than skipping.
