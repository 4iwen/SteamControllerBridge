import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let puckDetectorService = PuckDetectorService()
    private let controllerConnectionService = ControllerConnectionService()
    private let localBridgeServer = LocalBridgeServer()
    private let wineBridgeInstaller = WineBridgeInstaller()
    private let statusMenuFormatter = StatusMenuFormatter()
    private var puckStates: [PuckState] = []
    private var controllerState = ControllerConnectionState.notConnected
    private var bridgeStatus = LocalBridgeStatus.initial
    private var installStatus = WineBridgeInstallStatus.initial
    private let diagnosticsWindowController = DiagnosticsWindowController()

    private let statusMenuItem = NSMenuItem(title: "Status: No puck detected", action: nil, keyEquivalent: "")
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
        menu.delegate = self

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: "Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "")
        )

        menu.addItem(
            NSMenuItem(title: "Install Wine Bridge", action: #selector(installWineBridge), keyEquivalent: "")
        )

        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        )

        return menu
    }

    private func setupServices() {
        puckDetectorService.onStateChange = { [weak self] state in
            self?.puckStates = state
            self?.updateMenu()
        }

        controllerConnectionService.onStateChange = { [weak self] state in
            self?.controllerState = state
            self?.localBridgeServer.update(controllerState: state)
            self?.updateMenu()
        }

        localBridgeServer.onStatusChange = { [weak self] status in
            self?.bridgeStatus = status
            self?.updateMenu()
        }

        localBridgeServer.start()
        puckDetectorService.start()
        controllerConnectionService.start()
        updateMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
    }

    private func updateMenu() {
        statusMenuItem.title = "Status: \(statusMenuFormatter.title(puckStates: puckStates, controllerState: controllerState))"
        setStatusIcon(statusIconName())
        diagnosticsWindowController.update(
            puckStates: puckStates,
            controllerState: controllerState,
            bridgeStatus: bridgeStatus,
            installStatus: installStatus
        )
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
        diagnosticsWindowController.update(
            puckStates: puckStates,
            controllerState: controllerState,
            bridgeStatus: bridgeStatus,
            installStatus: installStatus
        )
        diagnosticsWindowController.showWindow(nil)
        diagnosticsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func installWineBridge() {
        let panel = NSOpenPanel()
        panel.title = "Select Wine Prefix"
        panel.message = "Select the Wine prefix that contains drive_c/windows/system32."
        panel.prompt = "Install"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        let result = panel.runModal()
        guard result == .OK, let prefixURL = panel.url else {
            return
        }

        do {
            installStatus = try wineBridgeInstaller.install(into: prefixURL)
            showInstallResult(title: "Wine Bridge Installed", message: installStatus.message)
        } catch {
            installStatus = WineBridgeInstallStatus(
                selectedPrefixPath: prefixURL.path,
                message: error.localizedDescription
            )
            showInstallResult(title: "Wine Bridge Install Failed", message: error.localizedDescription)
        }

        updateMenu()
    }

    private func showInstallResult(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title.contains("Failed") ? .warning : .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
