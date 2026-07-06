# Webhook Payload Editor + Shared Editor Framework — Design Spec

## Overview

Turn webhook payloads into user-editable, reusable **templates**, with Discord as
one built-in template rather than a hardcoded special case. Unify the DSL `discord`
and `webhook` targets into a single `webhook` target that references a payload by
name. Ship an editor (raw body + validation + a variable-substitution helper) that
follows the same "library of built-ins + user items" pattern as the Pixels
animation-profile editor, and factor the shared parts of those editors into a small
common framework.

Two deliverables, one doc:
1. **Webhook payload editor** — the feature.
2. **Shared editable-library framework** — the reusable shell it's built on, which
   the animation editor retrofits onto (and rules adopt only where it fits).

## Decisions (from planning Q&A)

- **Body model:** raw templated body (text) + validation (detect bad JSON) + a
  helper listing the available substitution variables. (The richer "structured
  template tree" model is deferred; raw is the v1 surface.)
- **Reuse:** a saved payload is **body + method only** — no URL. The URL stays in
  the rule: `webhook <url> with <payloadName>`. Discord's built-in carries no URL.
- **Unification:** `discord <url>` becomes sugar for `webhook <url> with discord`.
  Existing `webhook <url>` and `discord <url>` rules keep working unchanged.
- **Editors:** unify the shared shell (list, provenance, new/duplicate/from-template,
  persistence, preview affordance) across animations and payloads; **do not force**
  the rules editor into the mold — adopt only what's smooth.
- **Rollout:** phased for development, likely shipped together.

---

## Current State

- Two hardcoded payload classes implement `WebhookPayload`
  (`lib/domains/roll_parser/target_dtos.dart`):
  - `RollResultDTO` — generic JSON (`rule`, `aggregate`, `timestamp`, `matched_range`,
    `result_dice[]`, `all_dice[]`, `actions[]`).
  - `DiscordRollDTO` — a fixed embed: `title: "Rule: <name>"`, one Aggregate field,
    one field per die (`name`, `value (type)`). **No color, no custom text.**
- Two DSL target types (`ResultTargetType.webhook`, `.discord` in
  `result_targets.dart`); both fire through `WebhookDomain.fireWebhook(url, method,
  payload)`. Discord is always POST.
- `WebhookDomain.fireWebhook` gates on the global webhooks-enabled setting, sets
  `User-Agent`, and for POST sends `application/json` (which triggers a CORS
  preflight on web — pre-existing constraint).

---

## Data Model

```dart
class PayloadTemplate implements EditableLibraryItem {
  final String id;          // UUID for user items; stable slug for built-ins ("discord")
  final String name;        // user-facing + the `with <name>` reference key
  final String category;    // "discord" | "generic" | "custom" (grouping in the list)
  final bool isBuiltin;     // built-ins are read-only (duplicate to edit)
  final String method;      // "GET" | "POST" — transport: URL query vs request body
  final PayloadFormat format; // json | form | text | xml — drives escaping + content-type
  final String? contentType;  // override; defaults from format
  final Map<String, String> headers; // static custom headers (auth, vendor, …)
  final String body;        // the raw template text (see Templating)
}

enum PayloadFormat { json, form, text, xml }
```

`method` and `format` are independent (the "advanced options" of the editor):
`method` chooses *where* the rendered output goes; `format` chooses *how* values are
escaped, the array-join, and the `Content-Type`. GET is normally `form` (a query
string); POST is usually `json` but can be `form`/`text`/`xml`.

- Built-ins are defined in code (like `kBuiltinProfiles`) and exposed through the
  repository; user items live in `SharedPreferences`.
- `name` doubles as the DSL reference key, so it must be unique across the merged
  built-in + user set (enforced at save; see Issue H).

---

## Templating

A template is raw text with substitution tokens. Rendering takes a
`PayloadContext` (the roll data) and produces the request payload in the template's
**render mode** (JSON body for POST, query string for GET — see Render Modes).

### Grammar

- **Scalar** — `{path.to.value}`: a dotted lookup into the render context. Numeric
  segments index arrays (`{resultDice.0.name}`).
- **`{die.*}` — the die in scope**: inside a loop it's the current die; at top level
  it's the **first result die**. This makes the common single-die case
  (`{die.name}` rolled `{die.value}`) a one-liner with no loop — the headline UX for
  one physical Pixels die. (Empty/`null` when there are no result dice.)
- **Loop** — `{#resultDice} … {/resultDice}` (or `{#allDice}`): renders the inner
  block once per die for multi-die rolls; the renderer joins iterations with the
  **mode separator** (`,` for JSON, `&` for query). Outer scalars stay accessible.
- **Conditional (phase 2)** — `{?die.battery} … {/?}`: renders the block only when
  the value is present/non-empty (optional fields like battery, or a null ruleName).

Grammar is deliberately tiny (scalars + one loop + one optional conditional): enough
to express any real payload, small enough to learn from the helper panel.

### Render context (everything the renderer exposes)

```
# roll data
rule:       { name, displayName, id }
rollType:   "max" | "min" | "sum" | "rule" | "normal"
aggregate:  int
timestamp:  ISO-8601 string
matched:    { start, end, startInclusive, endInclusive }
resultDice: [ { name, type, value, battery, id, color, colorInt } ]  # the selected/result dice
allDice:    [ { name, type, value, battery, id, color, colorInt } ]  # every die in the roll

# rule outputs — what the rule *did* for this roll, not just the roll
threshold:  int | null             # when the rule used $THRESHOLD
modifier:   int | null             # when the rule used $MODIFIER
blink:      { color, colorInt, style } | null   # the blink fired in THIS result block (reactive)
actions:    [ { type, args } ]     # every co-action fired in this result block
```

`color`/`colorInt` (die *and* `blink`) are the same value as `#RRGGBB` and as a
decimal integer — Discord embed `color` wants the int form (Issue D), so a template
can tint an embed with a die's color (`"color": {die.colorInt}`) or with the rule's
**reactive** blink color (`"color": {blink.colorInt}` — the color the rule chose for
the matched range, so the message reflects the roll outcome, not a fixed value).
`{blink.*}` is the convenience view of the first blink co-action; `{actions}` exposes
them all generically.

Convenience derived tokens (so simple cases need no loop):
- `{resultDice.count}` / `{allDice.count}`
- `{resultDice.names}` — comma-joined friendly names
- `{resultDice.values}` — comma-joined values (e.g. for a delimited query param)
- `{resultDice.json}` / `{allDice.json}` — a ready-made JSON array of die objects

The editor's **helper panel** lists every leaf token and the loop/conditional blocks
with a one-line description and click-to-insert. This is the "what's available to
substitute" surface the feature is built around — it's generated from the context
schema so it can't drift from what the renderer actually supports.

### Render Modes & Structure

Serialization is **two orthogonal choices**. The renderer has only two body formats
(driven by `method`) and only ever substitutes + escapes *values* — it never
interprets key syntax. Everything else is how the *author* encodes structure within a
format.

**Axis 1 — body format (`method`):**

| Format | Method | Value escaping | Structure |
|--------|--------|----------------|-----------|
| **JSON body** | POST | JSON-escape strings; numbers bare | objects + arrays native — nothing extra to think about |
| **Query string** | GET | URL-encode all values | flat by default; nesting/arrays via Axis 2 |

Because JSON expresses structure natively, **Axis 2 only exists for GET.** RFC 3986
treats the query as opaque, so these are conventions — the author picks whichever
their endpoint parses; the renderer stays neutral.

**Axis 2a — object nesting** (author-typed keys):

| Convention | Author writes | Renders | Notes |
|-----------|---------------|---------|-------|
| Bracket | `roll[total]={aggregate}` | `roll[total]=17` | `qs`/PHP/Rails/Express, OpenAPI `deepObject` — safest default |
| Dot | `roll.total={aggregate}` | `roll.total=17` | framework-specific parsing; less widely supported |

**Axis 2b — arrays / collections** (which token/construct you use):

| Convention | Author writes | Renders | Notes |
|-----------|---------------|---------|-------|
| Repeated params | `{#resultDice}dice[]={die.value}{/resultDice}` | `dice[]=5&dice[]=12` | the `&`-join loop; OpenAPI `explode`/`form` |
| Delimited | `dice={resultDice.values}` | `dice=5,12,3` | uses the comma-joined `.values` token; OpenAPI `form`(non-explode)/`pipeDelimited` |
| Embedded JSON | `payload={resultDice.json}` | `payload=%5B%7B…%7D%5D` | full structure in one value; the escape hatch |

The two axes compose (a bracket-array of nested objects:
`dice[0][value]={die.value}`). In JSON mode all of this is just native `[]`/`{}`.

**Engine takeaway:** two serializers (JSON body, query+URL-encode); **nesting is
neutral key-passthrough; arrays are whichever token the author picks** (`loop` /
`.values` / `.json`) joined per mode (`,` in JSON, `&` in query).

### Wire format (advanced options, per payload)

`method` (Axis 1) is only *transport* — GET puts the render in the URL query, POST
puts it in the body. The **`format`** is the real serialization knob: it picks the
escaping, the array-join, and the `Content-Type`. Exposed under an "Advanced" section
in the editor, per payload.

| Format | `Content-Type` | Escaping | Array-join | Structure | Priority |
|--------|----------------|----------|-----------|-----------|----------|
| **json** | `application/json` | JSON-escape strings; numbers bare | `,` | native `{}` / `[]` | v1 (default; Discord) |
| **form** | `application/x-www-form-urlencoded` | URL-encode | `&` | bracket/repeated (Axis 2) | v1 |
| **text** | `text/plain` | none — author owns escaping | n/a | freeform | v1 (raw escape hatch) |
| **xml** | `application/xml` | XML-escape (`< > & "`) | (author tags) | author-typed tags | later |
| ~~multipart~~ | `multipart/form-data` | — | — | files | out of scope |

Key point: **`form` is the same serializer as the GET query mode**, just written to
the POST body with a form `Content-Type` — GET-query and POST-form differ only in
transport. So the engine still has just the three escaping strategies
(`json-escape` / `url-encode` / `none`, + `xml-escape` if/when XML lands).

Additional per-payload options:
- **`contentType` override** — vendor types or a charset (`application/json; charset=utf-8`).
- **`headers`** — static custom headers: `Authorization: Bearer …`, `X-Webhook-Secret`,
  vendor headers. (Computed **HMAC/signature** headers are a separate, later item —
  they need the rendered body, not a static value.)

Validation is format-aware: `json` → `jsonDecode`; `form` → well-formed pairs;
`xml` → well-formed; `text` → no structural check.

### Discord built-in (illustrative, POST)

```json
{
  "embeds": [{
    "title": "{rule.displayName} — rolled {aggregate}",
    "color": 5793266,
    "fields": [
      {#resultDice}{ "name": "{die.name}", "value": "{die.value} ({die.type})", "inline": true }{/resultDice}
    ]
  }]
}
```

Users start from this, tweak the color/title, and get a working custom Discord
message — the "NAME rolled a DIEROLL" request becomes a one-line title edit.

### ⚠️ Issues surfaced by raw JSON templating

- **Issue A — JSON string escaping.** A die named `He said "hi"` (or with a newline)
  would break the body if substituted naively. **Resolution:** the renderer
  JSON-string-escapes scalar *string* substitutions by default; numeric tokens
  (`{aggregate}`, `{die.value}`) are inserted bare. Each token has a known type, so
  the renderer escapes correctly without the author thinking about it.
- **Issue B — array commas in loops (resolved by normalization).** For the `json`
  format the rendered text is **leniently parsed (trailing/duplicate commas allowed)
  and re-serialized** before sending. So comma mistakes — a trailing comma after the
  last loop iteration, or one the author added by habit — are auto-fixed; the loop's
  auto-join is just a convenience, not a constraint. The same pass does
  **pretty-print for preview, minified for the wire** (Issue B2). (`form`/`text`/query
  pass through unchanged — no JSON normalization.) `{resultDice.json}` still exists
  for users who don't want per-die formatting at all.
- **Issue B2 — pretty vs minified.** JSON preview is pretty-printed (indented) for
  readability; the request body is the minified re-serialization from the same
  normalization pass. One pipeline, two outputs.
- **Issue C — validation is two-layered.** (1) Static: unknown `{tokens}` and
  unbalanced `{#..}{/..}` blocks flagged as you type. (2) Rendered: render against a
  sample context and parse the result in the template's mode (`jsonDecode` for POST,
  well-formed query for GET); surface errors with position. Escaping (Issue A) is
  what keeps "valid on sample" ⇒ "valid on real data." See Live Preview for the
  sample set + real-roll rendering.
- **Issue D — Discord color is a decimal int**, not a hex string
  (`"color": 5814783`, not `"#58CCFF"`). The helper documents this and the Discord
  built-in seeds a real value; consider a small "hex → int" affordance later.

---

## Rendering & Domain

- New pure `PayloadRenderer.render(PayloadTemplate, PayloadContext) → String` (body)
  in core/domain — replaces the two hardcoded `toJson()` methods. `PayloadContext`
  carries the same data `RollResultDTO.fromRollData` already collects.
- `WebhookDomain` gains template resolution: given a payload **name**, look it up
  (name-unique; see Issue H), render in the template's mode, and fire. Method +
  render mode come from the template (POST→JSON body, GET→query). The existing
  enabled-check / headers / send path is unchanged.
- The two `DTO` classes are retired; `RollResultDTO`'s JSON becomes the **"Generic
  JSON" built-in template**, and `DiscordRollDTO`'s becomes the **"Discord (Classic)"
  built-in**, so byte-compatibility with today's output is preserved (and testable).

### Built-in presets shipped

- **Discord (Classic)** (POST/json) — **byte-for-byte the current Discord message**
  (our adaptation of the official Pixels app format, commit `1937d86`): `title:
  "Rule: {rule.name}"`, a `timestamp`, an `Aggregate` field, then one field per die
  (`{die.name}` → `{die.value} ({die.type})`). The current format **omits the embed
  `color`** — not a Discord limitation (embeds fully support a `color` field), just
  what today's output does; we preserve it exactly. This is what `discord <url>`
  resolves to — existing rules render identically (sample 2). Golden-tested against
  today's `DiscordRollDTO` output.
- **Discord Message** (POST/json) — the simple `content` one-liner (sample 1); the
  friendly starting point most people actually want.
- **Discord Colored** (POST/json) — showcases the embed `color` field (which Discord
  supports): one embed per die tinted with `{die.colorInt}`, or a title embed tinted
  with the reactive `{blink.colorInt}` (samples 13/14). *Note:* the only color Discord
  can't do is coloring individual words in a plain `content` message — so per-die
  color is expressed as per-die embeds, not colored text.
- **Generic JSON** (POST/json) — today's `RollResultDTO`; the default for bare `webhook`.
- **Generic GET** (GET/form) — `rule` + `aggregate`; the default for bare `webhook GET`.

These are all **ordinary library entries** — same model, list, and editor as any
user payload; nothing is a hardcoded rendering path. "Discord (Classic)" and "Generic
JSON"/"Generic GET" are just the entries that reproduce today's output, and the DSL
keywords resolve into the library by name (`discord` → the Classic entry, bare
`webhook`/`webhook GET` → the Generic entries). Users can view, duplicate, or start
from any of them. The only thing distinguishing the three anchors is a **golden test**
pinning their templates to current output for backward compatibility; the others are
purely additive.

---

## DSL Changes

```
webhook <url>                          # default generic JSON payload, POST
webhook <url> with <payloadName>       # named payload template (mode from the template)
webhook GET <url> with <payloadName>   # GET template → query string
discord <url>                          # DEPRECATED sugar → webhook <url> with discord
```

The method can come from either the DSL (`GET`/`POST` token, as today) or the named
template; if both are present the DSL token wins and the template must be authored
for a compatible mode (validated at fire time; mismatch logs + skips).

- Parser (`result_targets.dart`): `webhookP` already captures rest-of-line into
  `target`. Add optional trailing ` with <name>` parsing → store the payload name in
  `args`. Keep `discord` as its own keyword that resolves to the `discord` payload.
- `ResultTargetFunction` shape is unchanged (name rides in `args`); evaluator passes
  the resolved payload to `WebhookDomain`.
- **Backward compatibility:** no forced migration — old rules parse and render
  identically (generic for `webhook`, Discord Classic for `discord`). The `discord`
  keyword still works but is **deprecated** (below), with an opt-in one-tap migrate.

### ⚠️ Issue E — `with <name>` portability

Like the named-webhook-config `@name` idea (`memory/custom_webhooks_design`), a
`with <payloadName>` reference is opaque when a rule's text is exported/shared — the
payload lives in app storage. Acceptable for v1; note for a future "export bundles
referenced payloads" story. Interplay with `@name` endpoint configs (if built later)
is complementary: `webhook @myEndpoint with discord`.

### ⚠️ Issue F — target keyword vs payload name

`discord` is both a keyword and the built-in payload's name. Keep the keyword for
back-compat; internally it's just `with discord`. Avoid letting a user name a custom
payload `discord` (reserve built-in names at save time).

### Deprecating the `discord` keyword

Once `discord <url>` is exactly `webhook <url> with discord`, the keyword is redundant
and should be **explicitly deprecated** — still working, but visibly on its way out and
easy to migrate. (This deprecates the *keyword*, not the Discord payload — the "Discord
(Classic)" library entry stays; migrated rules render identically.)

**Code:**
- `@Deprecated('Use `webhook <url> with discord`')` on `ResultTargetType.discord` and
  the `discordP` parser branch. Its dartdoc points at the replacement.
- The parser still accepts `discord` but tags the target `deprecated: true` (a flag on
  `ResultTargetFunction`, surfaced in the parse result's diagnostics) so the UI and a
  one-time log can react. The evaluator resolves it to the `discord` payload as before
  (no behavior change).
- Built-in default rules stop using the `discord` keyword so we don't ship deprecated
  syntax: the `webhookExample` demo rule (`parser_rules.dart:147`) migrates its
  `on result [*:*] discord <url>` line to `webhook <url> with discord`.

**UI:**
- In the **rules list**, a rule whose script uses `discord` shows a small deprecation
  glyph (e.g. a muted ⚠ badge) next to its name.
- Tapping it opens a short popup: *"The `discord` target is deprecated — use `webhook
  <url> with discord`. It still works for now."* with a **"Migrate"** button that
  rewrites `discord <url>` → `webhook <url> with discord` in place (safe, identical
  output) and re-saves the rule.
- In the **rule editor**, the same deprecation shows as a non-blocking inline warning
  (not an error — the rule is still valid), with the same one-tap fix.

**Removal:** keep the keyword through a deprecation window (at least one minor release
with the warning + migrate action), then remove `ResultTargetType.discord` and the
parser branch in a later major. Auto-migration means no user is stranded.

### ⚠️ Issue G — GET webhooks (resolved: supported)

GET payloads are first-class via the query render mode (see Render Modes), URL-encoded
on render. And GET is **not** limited to flat data: nesting/arrays are expressed with
the same text template via bracket notation (`user[name]={rule.name}`), the `&`-join
loop (`{#resultDice}dice[]={die.value}{/resultDice}`), or an embedded-JSON param
(`payload={resultDice.json}`) — all conventions (`qs`/PHP/Rails, OpenAPI `deepObject`),
since RFC 3986 leaves query serialization to convention. The renderer substitutes +
URL-encodes values and stays out of key syntax. The old fixed-query behavior
(`rule` + `aggregate`) becomes the **"Generic GET" built-in**, so bare
`webhook GET <url>` still behaves as before. Discord stays POST (it requires a JSON
body).

---

## Defaults & Fallbacks

Everything is pre-filled so a user gets a working webhook with just a URL; every knob
has a sensible default.

**New payload (from "New" / blank):**
- `method` = **POST**, `format` = **json**
- `body` = the **Generic JSON** built-in's template (a valid, complete starting
  point — never an empty box)
- `contentType` = **null** → derived from `format` (`application/json`)
- `headers` = **{}** (the domain already sets `User-Agent`; `Content-Type` is auto)
- `category` = **custom**, `name` = prompt (required; uniqueness enforced on save)

**Smart method↔format linkage in the editor:** choosing **GET** defaults `format` to
**form** (a query string); choosing **POST** defaults it to **json**. The user can
still override (POST + form/text), but the common path needs no thought.

**DSL defaults (no `with` clause):**
- `webhook <url>` → **Generic JSON** (POST) — unchanged from today
- `webhook GET <url>` → **Generic GET** (`rule` + `aggregate` query) — unchanged
- `discord <url>` → **Discord** built-in

**Missing / null value rendering** (keeps output valid without requiring the `{?…}`
conditional — see Q6):
- JSON: a null/absent scalar renders as the JSON literal `null` (so
  `"battery": {die.battery}` → `"battery": null`, still valid), strings as `""`.
- form / query: renders as empty (`battery=`).
- text: renders as empty string.
This default is *why* the conditional block can be deferred: optional fields never
produce invalid output.

**Preview source default:** the **canned sample** context (deterministic, covers
edge cases); "last real roll" is an opt-in toggle that falls back to the sample.

**Discord built-in defaults:** `color` = **5793266** (Discord blurple `#5865F2`),
`title` = `{rule.displayName} — rolled {aggregate}`, one inline field per result die.

---

## Persistence

- `WebhookPayloadRepository` (interface + `SharedPrefs…` impl), mirroring
  `PixelProfileRepository`: `builtins()`, `loadUserItems()`, `save()`, `delete()`.
- New `AppService` keys: `webhook_payloads` (JSON list). Two methods
  `getWebhookPayloads()` / `saveWebhookPayloads(...)`.

### ⚠️ Issue H — name resolution & collisions

Merged lookup by `name` needs a defined precedence. **Resolution:** user items
shadow built-ins of the same name is *disallowed* — built-in names are reserved; save
rejects a user payload whose name collides with a built-in or another user payload.
Lookup is then unambiguous.

---

## UI

Two screens, both on the shared framework (below), MVVM + Command:

- **Webhook Payloads list** (`WebhookPayloadsScreen`) — sections for built-in and
  your payloads; per-row: **Use** (copy the `with <name>` snippet / show usage),
  **Duplicate**, **Edit** (user only), **Delete** (user only). A "New" / "Start
  from…" picker (the Pixels `_PresetPickerSheet` generalized).
- **Payload editor** (`WebhookPayloadEditorScreen`) — name field, method (POST),
  a **raw body text editor** (monospace, JSON), a **variable helper panel**
  (click-to-insert palette from the Templating list), inline **validation** (Issue C),
  and a **live preview** (below).

Entry point: a `ListTile` in `AppSettingsWidget` near the Webhooks toggle.

### Live Preview

Two selectable preview sources, rendered in the template's mode with validation
status shown:

1. **Canned sample context** — a fixed fixture engineered to exercise every case, so
   "looks right in preview" means "works in production":
   - multiple dice of different types (e.g. d6, d20, d00) so loops and `count` are
     exercised;
   - a die whose name contains `"` and a newline (proves escaping, Issue A);
   - a die with `battery == null` (optional-field / conditional path);
   - a rule *with* a display name and a `max`-type roll (operator/rollType path);
   - an empty `resultDice` case toggle (loop over nothing → valid empty array/query).
   This fixture is a shared test fixture too, so the preview and the render tests use
   the same inputs.
2. **Last real roll** — render against the most recent actual roll for a true-to-life
   check (falls back to the canned sample when there's no roll yet).

Preview output is pretty-printed for JSON (POST) or shown as the decoded query
key/values (GET), with parse errors surfaced inline.

---

## Shared Editable-Library Framework

Animations (Pixels profiles), payloads, and — partially — rules are the same *shape*
of feature: a library of built-in + user items, a list screen with
new/duplicate/from-template/edit/delete, an editor with preview, and repository
persistence. Factor the **shell**; keep the **content body** specialized.

### Shared abstractions

```dart
abstract interface class EditableLibraryItem {
  String get id;
  String get name;
  String get category;
  bool get isBuiltin;
}

abstract interface class LibraryRepository<T extends EditableLibraryItem> {
  List<T> builtins();
  Future<List<T>> loadUserItems();
  Future<void> save(T item);
  Future<void> delete(String id);
}
```

- **`LibraryScreen<T>`** — a generic list widget: built-in/yours sections, a
  status-badge slot, a primary-action slot, and standard duplicate/new/from-template/
  delete wiring. (`PixelsProfilesScreen`'s structure, generalized.)
- **`LibraryEditorScaffold`** + **`LibraryEditorViewModel<T>`** — name field + a
  **content-body slot** + a **preview slot** + save/cancel, Command-based.

### Specialized bodies (stay separate)

- Animations → structured pixel/gradient forms + on-die preview.
- Payloads → raw template editor + variable helper + sample-roll preview.
- Rules → DSL text editor + DSL-test-harness preview.

### Mapping & retrofit order

1. **Build the framework + the payload editor on it** (greenfield, lowest risk).
2. **Retrofit the Pixels profile screens** onto it (proven pattern, net cleanup).
3. **Rules: adopt only what's smooth.** The list/provenance and repository
   conventions may share; the rule editor's body (DSL text) and its richer lifecycle
   (hide/unhide defaults, enable-toggle, reorder) stay custom. **Do not force it.**

### ⚠️ Issue I — over-abstraction risk

The three editors' *bodies* genuinely differ; only the shell is common. Keep the
framework a thin shell (list + lifecycle + persistence + preview affordance). If a
generic abstraction starts needing per-type special-casing in the shell, that's the
signal to stop generalizing and let the type keep its own code. Rules are the canary.

---

## Samples (the canned preview context + gallery)

All samples render against this fixed context (also the Live Preview canned sample
and the render-test fixture):

```
rule:     { name: "attackRoll", displayName: "Attack Roll" }
rollType: "max"
aggregate: 18
timestamp: "2026-07-06T21:15:00Z"
matched:  { start: 15, end: 20 }
resultDice:
  0: { name: "Gandalf",   type: "d20", value: 18, battery: 87,   color: "#5865F2", colorInt: 5793266 }
  1: { name: "Shadowfax", type: "d20", value: 11, battery: null, color: "#2ECC71", colorInt: 3066993 }
```

**1. Discord one-liner — the requester's ask** (POST · json · category discord)
```json
{ "content": "**{die.name}** rolled a **{die.value}** on their {die.type}!" }
→ { "content": "**Gandalf** rolled a **18** on their d20!" }
```

**2. Discord (Classic) — byte-for-byte the current message** (POST · json; what `discord <url>` resolves to)
```json
{ "embeds": [{
    "title": "Rule: {rule.name}",
    "timestamp": "{timestamp}",
    "fields": [
      { "name": "Aggregate", "value": "{aggregate}", "inline": false }
      {#resultDice}, { "name": "{die.name}", "value": "{die.value} ({die.type})", "inline": true }{/resultDice}
    ]
}] }
```
Renders (minified on the wire) identical to today's `DiscordRollDTO`:
```json
{"embeds":[{"title":"Rule: attackRoll","timestamp":"2026-07-06T21:15:00Z","fields":[{"name":"Aggregate","value":"18","inline":false},{"name":"Gandalf","value":"18 (d20)","inline":true},{"name":"Shadowfax","value":"11 (d20)","inline":true}]}]}
```
(no `color` — matches current output; the colored variants are samples 13/14)

**3. Generic JSON built-in** (POST · json) — today's `RollResultDTO` shape, verbatim.

**4. Generic GET built-in** (GET · form)
```
rule={rule.name}&aggregate={aggregate}   →   rule=attackRoll&aggregate=18
```

**5. Slack incoming webhook** (POST · json)
```json
{ "text": "🎲 {die.name} rolled {die.value} on a {die.type} (rule: {rule.displayName})" }
→ { "text": "🎲 Gandalf rolled 18 on a d20 (rule: Attack Roll)" }
```

**6. Form-encoded POST** (POST · form — same serializer as GET, in the body)
```
character={die.name}&result={die.value}&type={die.type}
→ character=Gandalf&result=18&type=d20      (Content-Type: application/x-www-form-urlencoded)
```

**7. GET, per-die array (repeated params)** (GET · form)
```
rule={rule.name}&{#resultDice}die[]={die.value}{/resultDice}
→ rule=attackRoll&die[]=18&die[]=11
```

**8. GET, bracket-nested object** (GET · form)
```
roll[rule]={rule.name}&roll[total]={aggregate}   →   roll[rule]=attackRoll&roll[total]=18
```

**9. GET, embedded JSON param** (GET · form)
```
event=roll&data={resultDice.json}
→ event=roll&data=%5B%7B%22name%22%3A%22Gandalf%22%2C%E2%80%A6%7D%5D
```

**10. Plain text / raw** (POST · text)
```
{die.name} rolled {die.value}   →   Gandalf rolled 18      (Content-Type: text/plain)
```

**11. Escaping (auto)** — die name `Sir "Rolls" a Lot`, `{ "content": "{die.name}!" }`
```json
→ { "content": "Sir \"Rolls\" a Lot!" }          (json: string auto-escaped, stays valid)
→ content=Sir%20%22Rolls%22%20a%20Lot         (form/query: URL-encoded)
```

**12. Null handling** — Shadowfax has `battery: null`
```json
{#resultDice}{ "name": "{die.name}", "battery": {die.battery} }{/resultDice}
→ { "name": "Gandalf", "battery": 87 },{ "name": "Shadowfax", "battery": null }
```
(null numeric → JSON `null`, output stays valid; no conditional needed)

**13. Discord message — one embed per die, each self-colored** (POST · json)
```json
{ "embeds": [ {#resultDice}{ "title": "{die.name}", "description": "rolled {die.value} on {die.type}", "color": {die.colorInt} },{/resultDice} ] }
→ { "embeds": [
     { "title": "Gandalf",   "description": "rolled 18 on d20", "color": 5793266 },
     { "title": "Shadowfax", "description": "rolled 11 on d20", "color": 3066993 }
] }
```
(note the **trailing comma** inside the loop — normalization strips the final one, so
the author doesn't manage separators)

**14. Reactive title color from the rule's blink** (POST · json)
Rule: `on [15:20] action blink green` + `... with discord` — the fired blink is the
rule's reaction to the total.
```json
{ "embeds": [{ "title": "Attack Roll — rolled {aggregate}!", "color": {blink.colorInt} }] }
→ { "embeds": [{ "title": "Attack Roll — rolled 18!", "color": 3066993 }] }   // green
```

### With rules (end-to-end)

Full DSL rules showing how a `webhook … with <payload>` target combines with the rest
of a rule. The payload named in `with` is a library entry (above).

**R1 — the requester's whole ask: "NAME rolled X" to Discord** (payload = *Discord Message*)
```
define attackRoll "Attack Roll" for roll *d20
  make selection @ALL
  use selection @ALL
    aggregate over selection sum
    on result [*:*] webhook https://discord.com/api/webhooks/… with discord-message
```
→ posts `**Gandalf** rolled a **18**!`

**R2 — reactive embed color (crit / normal / fail)** (payload = *reactive-embed*:
`{ "embeds": [{ "title": "{rule.displayName}: {aggregate}", "color": {blink.colorInt} }] }`)
```
define d20Check "d20 Check" for roll *d20
  make selection @ALL
  use selection @ALL
    aggregate over selection sum
    on result [20:20] action blink green
    on result [20:20] webhook <discord-url> with reactive-embed
    on result [2:19]  action blink white
    on result [2:19]  webhook <discord-url> with reactive-embed
    on result [1:1]   action blink red
    on result [1:1]   webhook <discord-url> with reactive-embed
```
The webhook shares the block's blink, so the embed color tracks the outcome: roll 20 →
green embed, roll 7 → white, roll 1 → red. (`{blink.*}` = the co-action in the same
`on result` range.)

**R3 — multi-die, per-die colored embeds** (payload = *Discord Colored*, sample 13)
```
define partyRoll "Party Roll" for roll *d*
  make selection @ALL
  use selection @ALL
    aggregate over selection sum
    on result [*:*] webhook <discord-url> with discord-perdie
```
→ two embeds, Gandalf (blurple) + Shadowfax (green).

**R4 — classic Discord, unchanged (backward compat)**
```
define logIt for roll *d*
  make selection @ALL
  use selection @ALL
    aggregate over selection sum
    on result [*:*] discord https://discord.com/api/webhooks/…
```
→ today's exact message (`discord` = `with discord`; Discord Classic).

**R5 — several targets in one block coexisting** (blink + JSON POST + GET ping)
```
define homeLog "Home Log" for roll *d*
  make selection @ALL
  use selection @ALL
    aggregate over selection sum
    on result [15:*] action blink green
    on result [15:*] webhook POST https://ha.local/api/webhook/roll
    on result [15:*] webhook GET https://ntfy.sh/mydice with ntfy-ping
```
Bare POST → Generic JSON (its `actions` includes the green blink); the GET uses a
`ntfy-ping` payload (`title={rule.displayName}&message={die.name} rolled {die.value}`).
All three fire; a webhook failure doesn't stop the blink.

---

## Implementation Design (resolving the open hows)

### 1. Renderer engine (core, pure — the riskiest piece)

A tiny template compiler, no external engine:

1. **Scan** the template into nodes on one pass, disambiguating by the char after `{`:
   `{#name}` loop-open, `{/name}` loop-close, `{?path}`/`{/?}` conditional (phase 2),
   otherwise `{path}` scalar. `{{`/`}}` escape a literal brace.
2. **Parse** nodes into a tree (loops nest); unbalanced open/close → validation error.
3. **Render** by walking the tree with a **scope stack** (the current die inside a
   loop, roll context at top level). Each scalar resolves its dotted path (numeric
   segments index arrays; `die` = current-loop-die or first result die) against the
   scope, then is **escaped by mode** (json-escape contents / URL-encode / xml-escape
   / none). Loops render the body per item, joined by the **mode separator** (`,`/`&`).
4. **Normalize (json format only)**: lenient-parse the rendered string (trailing
   commas tolerated — a small tolerant parser or a `json5`-style dep) → re-serialize
   **pretty for preview, minified for the wire**. `form`/`query`/`text`/`xml` pass
   through.

**Null rule** (type-aware, keeps output valid): a null *numeric/bool* scalar → `null`
literal (unquoted JSON position); a null *string* → empty (`""` in the author's
quotes; empty in form/query). Normalization is the safety net for edge cases.

`~300–400` lines, entirely unit-testable off the canned fixture; this is where test
density goes.

### 2. `fireWebhook` / payload interface refactor

Retire `WebhookPayload` (the DTO interface). The rendered result is data, not a class:

```dart
class RenderedRequest {
  final String method;            // GET | POST
  final Uri url;                  // query already appended for GET
  final Map<String,String> headers; // content-type + custom
  final String? body;             // rendered body for POST; null for GET
}
```

`WebhookDomain` becomes: **resolve** payload by name → **build** `PayloadContext` →
**render** (via the engine, in the template's mode) → **assemble** `RenderedRequest`
(content-type from `format` + custom headers) → **send** (the existing enabled-check /
User-Agent / send path). The two hardcoded DTO classes are deleted; their JSON lives in
the Discord-Classic / Generic built-in templates.

Evaluator: the `webhook` and `discord` cases **collapse into one** — build a
`PayloadContext`, then `_webhookDomain.fire(url, method, payloadName, context)`
(`discord` passes `payloadName: 'discord'`). Deferred as an effect closure, as today.

### 3. `PayloadContext` assembly + rule outputs

`PayloadContext.fromEvaluation(...)` gathers what the two DTOs' `fromRollData` already
collected (rule, aggregate, timestamp, matched, result/all dice) **plus rule outputs**:
- `threshold` / `modifier` — from the eval params already threaded through the rule.
- `actions` — the `coActions` list the evaluator already builds (excludes webhooks).
- `blink` — scan `coActions` for the `blink` action, resolve its color arg via the
  **existing blink color parser** (name/hex → `Color`) → expose `{blink.color}`
  (`#RRGGBB`) + `{blink.colorInt}` + `{blink.style}`. `die.color`/`colorInt` reuse the
  same color→hex/int conversion on the die's configured blink color.

No new evaluator data — it's exposing what's already computed. The one new util is a
shared `Color → (#RRGGBB, decimalInt)` helper (used by die + blink tokens).

### 4. DI wiring

`WebhookDomain` gains a `WebhookPayloadRepository` ctor param; `di.dart` builds the
SharedPrefs-backed repo and injects it (next to the existing `httpClient`/`appService`).
The evaluator already holds `_webhookDomain`; no new evaluator deps.

### 5. Editor internals (frontend)

`WebhookPayloadEditorScreen` + VM (MVVM + Command):
- **Name** field; **Advanced** panel — `method`, `format`, `contentType` override, and
  a **headers** key/value editor (add/remove rows).
- **Body**: a monospace multi-line editor.
- **Variable helper**: a collapsible palette **generated from the `PayloadContext`
  schema** (so it never drifts), click-to-insert at the cursor; includes loop-block
  snippets (inserts `{#resultDice} … {/resultDice}`, not bare tags).
- **Live preview**: the VM re-renders on edit (debounced) against the selected source
  and shows the output (pretty JSON / decoded query) + validation status inline.
- **Preview source**: a **canned `PayloadContext` fixture** (`const`, shared with the
  render tests) or the **last real roll** (from roll history via the domain), toggle;
  falls back to the fixture when there's no roll.

### 6. Web / CORS & delivery (the web-audience risk)

- Custom **headers** (`Authorization`) and non-simple **content-types** trigger a CORS
  preflight many endpoints reject; on web these advanced options may silently fail.
- Plan: **surface fire failures** (close the existing `// TODO: surface CORS errors` —
  a per-payload last-send status / error, shown in the editor's "Test send" and logged
  visibly) rather than swallowing; and show an inline **"may not work on web (CORS)"**
  caveat when custom headers / non-JSON formats are set and we're on web
  (`PlatformInfo.isWeb`). Don't block them — native works; just be honest.
- A **"Test send"** button in the editor (fires the rendered request to the URL) makes
  CORS/endpoint problems visible during authoring instead of silently at roll time.

### 7. Dangling `with <name>` references

- **Save-time (rule editor):** if a rule references `with <name>` for a payload that
  doesn't exist, a non-blocking warning (like the deprecation warning) — the rule still
  saves.
- **Eval-time:** the domain's resolve returns null → log + skip that target (never
  throws), consistent with the existing "webhook failure doesn't stop the blink".

### 8. Framework sequencing (frontend)

**Build the payload editor concretely first** (its own screens/VM/repo), then **extract
the shared framework from the two working examples** (payloads + Pixels profiles) rather
than up front — avoids speculative abstraction (Issue I). So framework extraction moves
*after* the payload editor ships, and the Pixels retrofit validates the extraction.

---

## Implementation Order (phased)

Built **concrete first, framework extracted after** (Design §8) — the editor ships
before any shared abstraction.

1. **Renderer engine** (Design §1) + `PayloadTemplate` model + the built-in templates
   (Discord Classic, Discord Message, Discord Colored, Generic JSON, Generic GET), with
   **golden tests** that Classic / Generic-JSON / Generic-GET render byte-identically to
   today's `DiscordRollDTO` / `RollResultDTO` / GET query.
2. **`PayloadContext` assembly** (Design §3) incl. rule outputs + the shared
   `Color → (#RRGGBB, int)` helper.
3. **Domain + interface refactor** (Design §2, §4): `RenderedRequest`, `WebhookDomain`
   resolve→render→send, retire the DTOs, DI wires the repo. `WebhookPayloadRepository`
   + `AppService` persistence.
4. **DSL**: `webhook <url> with <name>` parsing; `discord` deprecated (annotation +
   flag + built-in `webhookExample` migrated); evaluator's webhook/discord cases
   collapse to one.
5. **Payload list + editor screens** (Design §5): raw editor, advanced options
   (format/content-type/headers), helper palette, validation, live preview, Test-send;
   dangling-ref + deprecation UI (Design §6, §7).
6. **Extract the shared framework** (Design §8) from the working payload editor.
7. **Retrofit Pixels profile screens** onto the framework (validates the extraction).
8. (Evaluate) rules adoption of the shared shell where smooth — only if it fits.

## Test Coverage

Render tests drive the **shared canned sample fixture** (Live Preview) so preview and
tests agree:

- **Render parity:** Discord / Generic-POST / Generic-GET built-ins vs the current
  output (golden — Discord & `RollResultDTO` bytes, and today's `rule`+`aggregate`
  query for GET).
- **Escaping:** POST — dice names with quotes/newlines stay valid JSON; numbers bare.
  GET — the same values URL-encoded.
- **Loops:** multi-die array has no trailing comma (POST) / correct `&`-joins (GET);
  empty `resultDice` → valid empty array / empty query.
- **Validation:** malformed template → mode-appropriate parse error surfaced; unknown
  token flagged; unbalanced `{#..}{/..}` block flagged.
- **DSL:** `webhook <url> with x` and `webhook GET <url> with x` parse; `discord <url>`
  resolves to the discord payload; DSL/template method-mismatch skips + logs; old
  `webhook`/`discord` rules unchanged (existing `dsl_webhook_*` tests).
- **Persistence:** save/load/delete; name-collision + reserved-name rejection.
- **Framework:** repository CRUD + `LibraryScreen` widget behavior, reused by both
  payloads and (post-retrofit) profiles.

## Open Questions / Risks

- **Q1 (resolved):** Custom minimal, mode-aware renderer (scalars + one loop + a
  phase-2 conditional; JSON-escape/`,`-join for POST, URL-encode/`&`-join for GET).
  Rejected stock Mustache (HTML-escaping is wrong for JSON; would need a custom escape
  hook and still wouldn't give the GET mode).
- **Q3 (resolved):** GET is supported via the query render mode (Issue G).
- **Q2:** Should the editor later offer a "Discord-friendly" knob panel (color picker,
  title field) layered over the raw body? Raw-only for v1 per decision; revisit.
- **Q4 (resolved):** Wire format is a per-payload advanced option (`format` +
  `contentType` + static `headers`). v1 = json / form / text (three escaping
  strategies); **deferred** = XML and computed HMAC/signature headers.
- **Q5:** Export portability of `with <name>` (Issue E) — future bundling story.
- **Q6 (leaning defer):** Conditional block (`{?..}`) — the null-rendering defaults
  (Defaults & Fallbacks) already keep optional fields valid (`null` / empty), so the
  conditional is a readability nicety, not required for correctness. Defer to phase 2
  unless a built-in needs it.
