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
2. Choose **Install Wine Bridge** from the menu bar item.
3. Select the Wine prefix folder.
4. The installer copies the 64-bit DLLs into `drive_c/windows/system32/` and
   the 32-bit DLLs into `drive_c/windows/syswow64/` when that directory exists.
5. It updates `user.reg` with global and Steam app-specific DLL overrides,
   including both plain and starred Wine override names.
   
   ```text
   xinput1_1=n,b
   xinput1_2=n,b
   xinput1_3=n,b
   xinput1_4=n,b
   xinput9_1_0=n,b
   xinputuap=n,b
   ```

   Quit all Wine/Steam processes before installing, then relaunch Steam so Wine
   reloads `user.reg`.
