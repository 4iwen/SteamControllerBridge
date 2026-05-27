import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let puckDetectorService = PuckDetectorService()
    private let controllerConnectionService = ControllerConnectionService()
    private var puckState = PuckState.notDetected
    private var controllerState = ControllerConnectionState.notConnected
    private let diagnosticsWindowController = DiagnosticsWindowController()
    private let settingsWindowController = SettingsWindowController()

    private let statusMenuItem = NSMenuItem(title: "Status: No puck detected", action: nil, keyEquivalent: "")
    private let deviceNameMenuItem = NSMenuItem(title: "Device: None", action: nil, keyEquivalent: "")
    private var currentStatusIconName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupServices()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard statusItem?.button != nil else { return }

        setStatusIcon("gamecontroller")

        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        deviceNameMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(deviceNameMenuItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: "Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "")
        )
        menu.addItem(
            NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        )

        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        )

        return menu
    }

    private func setupServices() {
        puckDetectorService.onStateChange = { [weak self] state in
            self?.puckState = state
            self?.updateMenu()
        }

        controllerConnectionService.onStateChange = { [weak self] state in
            self?.controllerState = state
            self?.updateMenu()
        }

        puckDetectorService.start()
        controllerConnectionService.start()
        updateMenu()
    }

    private func updateMenu() {
        statusMenuItem.title = "Status: \(mainStatusTitle())"
        deviceNameMenuItem.title = "Device: \(deviceNameTitle())"
        setStatusIcon(statusIconName())
        diagnosticsWindowController.update(puckState: puckState, controllerState: controllerState)
    }

    private func mainStatusTitle() -> String {
        if controllerState.controller_is_connected {
            return "Controller connected"
        }

        if puckState.is_present {
            return "Puck connected, controller off"
        }

        return "No puck detected"
    }

    private func deviceNameTitle() -> String {
        if let controllerName = controllerState.controller_name, controllerState.controller_is_connected {
            return controllerName
        }

        if let puckName = puckState.product_name, puckState.is_present {
            return puckName
        }

        if puckState.is_present {
            return "Steam Controller puck"
        }

        return "None"
    }

    private func statusIconName() -> String {
        if controllerState.controller_is_connected {
            return "gamecontroller.fill"
        }

        return "gamecontroller"
    }

    private func setStatusIcon(_ symbolName: String) {
        guard currentStatusIconName != symbolName else {
            return
        }

        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Steam Controller"
        ) else {
            return
        }

        currentStatusIconName = symbolName

        statusItem?.button?.contentTintColor = nil
        statusItem?.button?.image = whiteStatusImage(from: image)
    }

    private func whiteStatusImage(from sourceImage: NSImage) -> NSImage {
        let image = NSImage(size: sourceImage.size)
        image.lockFocus()

        sourceImage.draw(
            in: NSRect(origin: .zero, size: sourceImage.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        NSColor.white.set()
        NSRect(origin: .zero, size: sourceImage.size).fill(using: .sourceAtop)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Actions

    @objc private func showDiagnostics() {
        diagnosticsWindowController.update(puckState: puckState, controllerState: controllerState)
        diagnosticsWindowController.showWindow(nil)
        diagnosticsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
