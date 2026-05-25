import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // SF Symbol for the menubar icon — will swap this for a
        // "connected / disconnected" variant once HID detection is wired up.
        button.image = NSImage(
            systemSymbolName: "gamecontroller",
            accessibilityDescription: "Steam Controller"
        )
        button.image?.isTemplate = true   // respects light / dark menu bar

        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // status indicator - placeholder until controller detection is added
        let statusItem = NSMenuItem(title: "No controller detected", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        )

        return menu
    }

    // MARK: - Actions

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
