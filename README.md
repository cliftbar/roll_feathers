# Roll Feathers

Companion app for Bluetooth enabled dice.

**WARNING:** there will be constant breaking changes, and bad builds, for the foreseeable future.  Please report issues
or requests.

## Features
- Supported Dice
- [Pixel Dice](https://gamewithpixels.com/)
- [GoDice](https://particula-tech.com/pages/godice)
- Connect multiple dice
- Add virtual dice
- Track roll history
- Roll types
  - sum, max (advantage), min (disadvantage)
  - Blink the lowest or highest die when rolling max or min
- Blink Dice on roll
  - choose blink color
- Home Assistant light integration
  - Not available on web
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
