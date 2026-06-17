# Roll Feathers

Companion app for Bluetooth enabled dice.

**WARNING:** there will be constant breaking changes, and bad builds, for the foreseeable future. Please report issues
or requests.

1. [Features](#features)
2. [Platforms](#platforms)
3. [Install](#install)
   1. [Android](#android)
   2. [macOS](#macos)
   3. [Windows](#windows)
      - [Installed](#installed)
      - [Portable](#portable)
4. [Home Assistant](#home-assistant)
   1. [Setup](#ha-app-setup)
   2. [Home Assistant Web Setup](#ha-web-setup)
5. [API Server](#api-server)
6. [Webhooks & Discord](#webhooks--discord)
7. [dddice Integration](#dddice-integration)
8. [Rule Scripting](#rule-scripting)

## Features

- Connect multiple supported Bluetooth dice
  - [Pixel Dice](https://gamewithpixels.com/)
  - [GoDice](https://particula-tech.com/pages/godice)
  - Virtual Dice (with removal support)
- Track roll history
- Custom rule scripting via DSL
- Roll types & aggregates
  - sum, max (advantage), min (disadvantage)
  - Blink the lowest or highest die when rolling max or min
- Visual feedback on roll
  - Custom blink colors per die
  - **Rolling flash animations (Pixels only)** — configure color and animation style (Strobe, Pulse, Breathe)
  - **Preview animations** directly from settings
- Home Assistant integration for smart light control
- Webhook and Discord rule actions — fire HTTP requests or Discord embeds on roll result
- dddice integration — mirror physical dice rolls to a virtual tabletop room
- API server to get the latest roll (local network only)
  - `GET http://<device-ip>:8080/api/last-roll`
  - Not available on web
 
### DSL and Local Testing

- Authoring guide and reference: docs/dsl/roll_feathers_dsl_v1_1_guide.md
- Rule examples (including high/low variants): docs/dsl/
- CLI-style tester usage: docs/dsl/dsl_test_harness_usage.md
- Quick start: run `flutter test test/tools/dsl_tester_cli_test.dart --` with env vars `RULE_TEXT` and `DICE` (and optional `MODIFIER`, `THRESHOLD`). See the usage doc for details and examples.

## Platforms

- [x] Android
- [ ] iOS
  - build from source
- [x] macOS
- [x] Windows
- [ ] Linux
  - build from source
- [x] Web
  - Chromium-based browsers

## Install

All installers are currently unsigned, meaning you'll have to click past various security warnings to install the app.

### Android

- download apk or appbundle
- open downloaded apk
- a security popup will say that apps from unknown sources can't be installed
  - click on the settings option
- toggle "allow from this source"
- click install
- The phone may scan the app for malicious code, allow that, continue installation afterward.

### macOS

- download & open `dmg` file
- drag the roll feathers app into the application folder
- close and eject the dmg
- open the roll feathers app from the applications folder, there will be a security warning
- go to Settings → Privacy & Security → Security
  - there should be a button to open roll feathers anyway
  - Open anyway
- allow bluetooth permission when prompted

### Windows

Installed and portable versions are available

#### Installed

- download exe file
- open and run, follow installer prompts

#### Portable

- download zip
- extract to folder
  - there is not a containing folder in the zip, extract in a new empty folder
- run the contained `exe`

## Home Assistant

A Home Assistant integration is available for blinking lights on rolls.

## HA App Setup

- Create an [access token](https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token)
- Enable Home Assistant in the app
- Paste the access token plus the HA url and a default light entity to control into the Home Assistant Settings Page
  - The target entity can be set per die in the connected dice settings

### HA Web Setup

For Home Assistant to allow external access from the web client, the HA cors settings need to be configured.
See the Home Assistant [documentation](https://www.home-assistant.io/integrations/http/#cors_allowed_origins) for
details.

Example Config Block

```yaml
http:
  cors_allowed_origins:
    - https://rollfeathers.ungawatkt.com
```

## Api Server

The api server binds to all available interfaces on port 8080.
address: `http://localhost:8080`

### endpoints:

- `GET /api/last-roll`: return the most recent roll

## Webhooks & Discord

DSL rule actions can fire outbound HTTP requests or Discord embeds when a result range matches.

- Enable **Webhooks** in app settings to allow outbound requests (gated globally)
- Add `action webhook [GET|POST] <url>` or `action discord <webhook_url>` to any `on result` line in a rule
- POST sends a structured JSON payload (`RollResultDTO`) with rule name, timestamp, aggregate value, matched range, and dice details
- GET sends `rule` and `aggregate` as query parameters only
- Errors are caught and logged; dice behavior is never interrupted

See [Rule Scripting](#rule-scripting) for the DSL syntax and the built-in `Webhook Example` rule as a starting point.

## dddice Integration

Rolls made with connected physical dice can be mirrored to a [dddice](https://dddice.com) virtual tabletop room in real time.

### Setup

1. Enable **dddice** in app settings
2. Enter an API key (create one at dddice.com) — or leave blank to join as a guest under the name `bees`
3. Select a **room** from the room picker (rooms are fetched from your account)
4. Optionally set a **theme** per die in each die's settings

### How It Works

- Each physical dice roll is sent to the configured dddice room using the die's assigned theme
- Guest sessions automatically create a temporary room on first roll
- Themes are stored per die identifier and persist across sessions

## Rule Scripting

Rule scripts define custom actions triggered by a dice roll via a built-in DSL. Scripts filter dice into named selections, aggregate over them, and execute actions when the result falls in a specified range. See the [DSL v1.1 Authoring Guide](docs/dsl/roll_feathers_dsl_v1_1_guide.md) for the full reference and the [default rules](lib/domains/roll_parser/parser_rules.dart) for working examples.

### Script Structure

```
define <name> ["Display Name"] for roll <dice matcher>
  [make selection @<NAME> [from (@<PARENT> | $ALL_DICE)]
    [with <transform>]
    ...]
  use selection (@<NAME> | $ALL_DICE)
    aggregate over selection <aggregate>
    on result <range> action <action>
    ...
```

Blocks are ordered: all `make selection` blocks that a `use selection` needs must appear before it.

### Global Variables

- `$MODIFIER`: modifier value (defaults to 0)
- `$THRESHOLD`: threshold value (defaults to 0)
- `$ALL_DICE`: all dice in the roll
- `$ROLLED_COUNT` / `$ROLLED`: number of dice rolled (substituted at evaluation time)
- `$MAX` / `$MIN`: highest and lowest face values (substituted at evaluation time)

### Dice Matcher

Matches which roll triggers the script, using standard dice notation with wildcards:

- `*d*`: any number of any die type
- `1d10,1d00`: one d10 and one d00 (percentile — enter `0` as face count to create a virtual d00)
- `2d20`: exactly two d20s
- `*d6`: any number of d6s
- `3d*`: exactly three dice of any type

### Make Selection Blocks

Build a named selection by filtering and transforming the source dice:

- `with top N` / `with bottom N`: keep the N highest / lowest dice
- `with match [a:b]`: keep dice whose value falls in the range [a:b]
- `with dupes [a:b]`: keep dice in value-buckets with multiplicity in [a:b] (e.g. `[2:*]` for any duplicates)
- `with over N` / `with under N`: keep dice strictly above / below N
- `with offset X` / `with mul X` / `with div X`: apply math to all values in the selection

Transforms apply in order. Multiple `with` lines can be chained within one `make selection` block.

### Aggregates

Applied inside a `use selection` block to produce the numeric result:

- `sum`: total of all values
- `min` / `max`: lowest / highest value
- `avg`: average
- `count`: number of dice in the selection

### Result Ranges

`[` / `]` are inclusive endpoints; `(` / `)` are exclusive; `*` is open (unbounded).

- `[*:*]`: any value
- `[10:*]`: 10 or higher
- `[*:10)`: 9 or lower
- `(2:5)`: 3 or 4
- `[$MIN:$MIN]`: exactly the global minimum (all dice tied)

### Actions

- `action blink [color]`: blink the selection's dice the given color (default white)
- `action blink $ALL_DICE [color]`: blink all rolled dice
- `action sequence [loops] [colors...]`: cycle the selection's dice through a color list
- `action webhook [GET|POST] <url>`: fire an HTTP request (requires Webhooks enabled in settings)
- `action discord <webhook_url>`: post a Discord embed

### Example Scripts

Percentile roll (1d10 + 1d00), blink a color per bracket, rainbow on 99+:

```
define percentiles "Percentiles (1d10,1d100)" for roll 1d10,1d00
  use selection $ALL_DICE
    aggregate over selection sum
    on result [0:10)  action blink red
    on result [10:25) action blink orange
    on result [25:50) action blink yellow
    on result [50:75) action blink green
    on result [75:90) action blink blue
    on result [90:99) action blink purple
    on result [99:*)  action sequence 1 red orange green blue violet
```

Blink the top die after applying a modifier (advantage with modifier):

```
define maxWithModifier "Max (with Modifier)" for roll *d*
  # blink one die with the highest value after applying the modifier
  make selection @ALL_MOD from $ALL_DICE
    with offset $MODIFIER
    with top 1
  use selection @ALL_MOD
    aggregate over selection max
    on result [*:*] action blink blue
```

Highlight high (green) and low (red) dice; blink purple if all dice tie:

```
define highLowAllTiesExclusive "High/Low/Tie All" for roll *d*
  make selection @ALL_MAX with match [$MAX:$MAX]
  make selection @ALL_MIN with match [$MIN:$MIN]
  make selection @DUPE_ANY with dupes [2:*]
  # All-equal → purple only
  use selection @DUPE_ANY
    aggregate over selection count
    on result [$ROLLED:$ROLLED] action blink purple
  # Non-all-equal → highs and lows
  use selection @ALL_MAX
    aggregate over selection count
    on result [1:$ROLLED) action blink green
  use selection @ALL_MIN
    aggregate over selection count
    on result [1:$ROLLED) action blink red
```