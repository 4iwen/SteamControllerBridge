# SteamControllerBridge

MacOS menubar app for Steam Controller wine bridge.

## Requirements

- macOS 13+
- Xcode Command Line Tools
- SDL3: `brew install sdl3`

## Run

### Xcode

Open `SteamControllerBridge.xcodeproj`, not `Package.swift`.

Select the `SteamControllerBridge` scheme and run it. This builds a real menu-bar
`.app` with bundle id `dev.aiwen.SteamControllerBridge`.

In the target settings, set **Signing & Capabilities > Team** to your Apple
Development team if Input Monitoring keeps resetting between builds.

If SDL needs HID access, grant Input Monitoring to the built app once.

Raw SwiftPM builds still work, but macOS may ask for permissions again:

```bash
swift build
swift run
```
