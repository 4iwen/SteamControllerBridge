# SteamControllerBridge

A macOS menu-bar app for reading Steam Controller inputs over USB-C HID — no Steam required.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
# From the project root
swift build -c release

# Run the compiled binary
.build/release/SteamControllerBridge
```

The app appears only in the menu bar (no Dock icon). Click the gamepad icon → **Quit** to exit.

## Development (live-reload friendly)

```bash
swift run
```

## Project layout

```
SteamControllerBridge/
├── Package.swift
└── Sources/SteamControllerBridge/
    ├── main.swift          # Entry point, activation policy
    └── AppDelegate.swift   # Status item, menu, actions
```

## Roadmap

- [x] Menu-bar icon + Quit item
- [ ] IOKit / HID manager to detect Steam Controller 2 by USB vendor/product ID
- [ ] Poll or callback-based input reading (buttons, axes, trackpads)
- [ ] Key / mouse event remapping
