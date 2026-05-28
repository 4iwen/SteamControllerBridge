# SteamControllerBridge

MacOS menubar app for Steam Controller wine XInput bridge.

## Requirements

- macOS 13+
- Xcode Command Line Tools
- `brew install mingw-w64`

## Run

### Xcode

Open `SteamControllerBridge.xcodeproj`.

Select the `SteamControllerBridge` scheme and run it. This builds a real menu-bar
`.app` with bundle id `dev.aiwen.SteamControllerBridge`.

In the target settings, set **Signing & Capabilities > Team** to your Apple
Development team if Input Monitoring keeps resetting between builds.

Grant Input Monitoring to the built app once so it can read Steam Controller
HID input for diagnostics.

## Install

1. Run the app.
4. Choose **Install Wine Bridge** from the menu bar item.
5. Select the Wine prefix folder.
6. The installer copies the DLLs into `drive_c/windows/system32/` and updates
   `user.reg` so these DLL overrides are set to native, then builtin:
   
   ```text
   xinput1_3=n,b
   xinput1_4=n,b
   xinput9_1_0=n,b
   ```
