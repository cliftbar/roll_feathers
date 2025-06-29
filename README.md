# Roll Feathers

Companion app for Bluetooth enabled dice.

**WARNING:** there will be constant breaking changes, and bad builds, for the foreseeable future. Please report issues
or requests.

1. [Features](#features)
2. [Platforms](#platforms)
3. [Install](#install)
   1. [Android](#android)
   2. [Android](#macos)
   3. [Android](#windows)
      - [Installed](#installed)
      - [Portable](#portable)
4. [Home Assistant](#home-assistant)
   1. [Setup](#ha-app-setup)
   2. [Home Assistant Web Setup](#ha-web-setup)
5. [API Server](#api-server)
6. [Rule Scripting](#rule-scripting)

## Features

- Connect multiple supported Dice
  - [Pixel Dice](https://gamewithpixels.com/)
  - [GoDice](https://particula-tech.com/pages/godice)
  - Virtual Dice
- Track roll history
- Roll types
  - sum, max (advantage), min (disadvantage)
  - Blink the lowest or highest die when rolling max or min
- Blink Dice on roll
  - choose blink color
- Home Assistant light integration
- API to get the latest roll
  - GET http://<device-ip>:8080/api/last-roll
  - Not available on web

## Platforms

- [x] Android
- [ ] iOS
  - build from source
- [x] MacOs
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

### MacOS

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

## Rule Scripting

Rule scripts allow for custom actions on roll. Scripts can target specific die combinations and alter roll outcomes,
like adding a modifier value. The script structure is below:

```
define <name>
for roll <dice matcher>
transform
  with <transform function> <transform args>
aggregate max
with result
  on [<result min>:<result max>] <result type> <result function> <result args>
```

The [default rules](https://git.cliftbar.site/cliftbar/roll_feathers/src/branch/main/lib/domains/roll_parser/parser_rules.dart)
can used as a reference.

### Global Variables
The following variables are available for all scripts.
- `$MODIFIER`: modifier for the roll, defaults to 0. Not currently setable.
- `$THRESHOLD`: threshold for the roll, defaults to 0. Not currently setable.
- `$ALL_DICE`: Represent all dice in the roll.
- `$RESULT_DICE`: Represent all dice in the results.
- `$ROLLED_COUNT`: Represents the number of dice rolled.

### name

Name of the script

### Dice Matcher

What combination of dice are needed to evaluate the script. The format is similar to standard dice notation, like 1d6
or 2d10, and allows for wildcards. Some examples are below:

- `*d*`: match when any number of any die type are rolled
- `1d10,1d00`: match when one d10 and one d00 is rolled
- `2d20`: match when 2 d20s are rolled
- `*d6`: match when any number of d6's are rolled
- `3d*`: match when 3 of any die type is rolled

### Transform

The transform step applies to all die values in the roll. Values are either changed or filtered out.
The available transforms are:

- `top n`: returns the highest n values of the roll
  - Example: `roll 1,2,3,4,5; top 3; returns 3,4,5`
- `bottom n`: returns the lowest n values of the roll
  - Example: `roll 1,2,3,4,5; bottom 3; returns 1,2,3`
- `equals n`: returns only values that equal the argument, so "only leave dice that rolled a six"
  - Example: `roll 2,3,5,3,6; equals 3; returns 3,3`
- `match n`: return only values where at least n number of them are the same, for example `match 2` for doubles
  - If there are two sets of matches, the number with the most matches will be returned.
  - Example a roll of `roll 3,3,6,6,6; match 2; returns 6,6,6`, the 6's will be returned
- `over n`: returns all values above the given value
  - Example: `roll 2,4,6,8; over 5; returns 6,8`
- `under n`: returns all values under the given value
  - Example: `roll 2,4,6,8; under 5; returns 2,4`
- `mul n`: return all values multiplied by n
  - Example: `roll 3,4,3; mul 3; returns 9,12,9`
- `div n`: return all values divided by n, rounded
  - Example: `roll 3,4,56; div 2; returns 2,2,3,3`

Multiple transforms may be defined in a script, and they get applied in sequence. Example

```
roll: 7,3,5
...
transform
  with offset 5
  with top 2
...
```

Will result in values `12,10`

### Aggregates

Aggregates are how the final roll result gets determined. Aggregates apply to any roll
values remaining after the transform step.

The available aggregates are:

- `sum`: Add together all the rolls
- `min`: take the smallest remaining value
- `max`: take the highest remaining value
- `avg`: take the average of the values

### Result Targets

Result targets define what to do with the final computed result. Targets have two parts:
a value range, and a target function.

#### Range

The range defines what values will trigger what function. Ranges are formatted similar to mathematical range notation;
closed endpoints are shown with brackets, open with parenthesis, and 2 numbers separated by a `:`. The values may be
numbers or `*`.

Examples:

- `[*:*]`, `(*,*)`: trigger for any result
- `[3:*)`: trigger for result of 3 or higher
- `(2:5)`: trigger for results 3 or 4
- `(*:10)`: trigger for result of 9 or lower

#### Target functions

Target functions are run with the results of the roll. Every target has these available to it by default:

- Dice that were returned by the transform step
- All dice that were rolled

The available target functions are:

- `blink <dice set> color`: Blink the set of dice the specified color.
  If the set of dice to blink is not provided, dice that are left after the transform step are blinked.
  If a color is not given, it defaults to white
  - Examples:
    - `blink`: blink result dice (because of defaulting) white
    - `blink $ALL_DICE red`: blink all dice red
  - `blink $RESULT_DICE sheep`: blink the result dice the catan sheep color (light green)
- `sequence <dice set> <loops> [colors]`: cycle the specified dice through a set of colors, looping a number of times.
  If the set of dice to blink is not provided, dice that are left after the transform step are blinked.
  If the loops count isn't set, it defaults to 1.
  If colors are not given, it defaults to red, green, blue
  - Examples:
    - `sequence $ALL_DICE 2 red orange yellow green blue indigo violet`: make all dice go through rainbow colors
    - `sequence`: do a sequence call with default values

#### Result examples

Here are some examples putting everything in the results together

- Blink green with a result 10 or more, red if it's below a 10

```
with result
  on [*:10) action blink \$RESULT_DICE green
  on [10:*] action blink \$RESULT_DICE red
```

- Blink result dice blue for all results

```
with result
  on [*:*) action blink \$RESULT_DICE blue
```

- Blink all dice colors for the 10th, 25th, 50th, 75th, and 90th percentile, and play a rainbow on a 99

```
with result
  on [0:10) action blink \$ALL_DICE red
  on [10:25) action blink \$ALL_DICE orange
  on [25:50) action blink \$ALL_DICE yellow
  on [50:75) action blink \$ALL_DICE green
  on [75:90) action blink \$ALL_DICE blue
  on [90:99) action blink \$ALL_DICE purple
  on [99:*) action sequence \$ALL_DICE 2 red orange yellow green blue indigo violet
```

- Cycle through colors for catan resources for the starter board (with nothing for the robber)

```
with result
  on [2:3) action sequence 2 sheep
  on [3:4) action sequence 2 wood ore
  on [4:5) action sequence 2 wheat sheep
  on [5:6) action sequence 2 wheat brick
  on [6:7) action sequence 2 wheat brick
  on [8:9) action sequence 2 wood ore
  on [9:10) action sequence 2 wheat wood
  on [10:11) action sequence 2 brick ore
  on [11:12) action sequence 2 wood sheep
  on [12:12] action sequence 2 wheat
```

### Full Example Script
Make a percentile role with a modifier, a blink a color for the 10th, 25th, 50th, 75th, and 90th percentile results,
and cycle all the colors on a 99.
```
define percentiles
for roll 1d10,1d00
transform with offset \$MODIFIER
aggregate sum
with result
  on [0:10) action blink \$ALL_DICE red
  on [10:25) action blink \$ALL_DICE orange
  on [25:50) action blink \$ALL_DICE yellow
  on [50:75) action blink \$ALL_DICE green
  on [75:90) action blink \$ALL_DICE blue
  on [90:99) action blink \$ALL_DICE purple
  on [99:*) action sequence \$ALL_DICE 2 red orange yellow green blue purple
```