# SteamControllerBridge

MacOS menubar app for Steam Controller wine bridge.

## Requirements

- macOS 13+
- Xcode Command Line Tools

## Run

### Xcode

Open `SteamControllerBridge.xcodeproj`.

Select the `SteamControllerBridge` scheme and run it. This builds a real menu-bar
`.app` with bundle id `dev.aiwen.SteamControllerBridge`.

In the target settings, set **Signing & Capabilities > Team** to your Apple
Development team if Input Monitoring keeps resetting between builds.

Grant Input Monitoring to the built app once so it can read Steam Controller
HID input for diagnostics.
