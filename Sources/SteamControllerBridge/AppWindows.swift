import AppKit

final class DiagnosticsWindowController: NSWindowController {
    private let devicesView = NSTextView()
    private let infoView = NSTextView()
    private let inputView = NSTextView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Diagnostics"
        window.center()

        super.init(window: window)
        window.contentView = makeContentView()
        update(puckState: .notDetected, controllerState: .notConnected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(puckState: PuckState, controllerState: ControllerConnectionState) {
        devicesView.string = devicesText(puckState: puckState, controllerState: controllerState)
        infoView.string = infoText(puckState: puckState, controllerState: controllerState)
        inputView.string = "Input: not captured"
    }

    private func makeContentView() -> NSView {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        tabView.addTabViewItem(tab(title: "Devices", view: scrollView(for: devicesView)))
        tabView.addTabViewItem(tab(title: "Info", view: scrollView(for: infoView)))
        tabView.addTabViewItem(tab(title: "Input", view: scrollView(for: inputView)))

        let container = NSView()
        container.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func scrollView(for textView: NSTextView) -> NSScrollView {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }

    private func devicesText(puckState: PuckState, controllerState: ControllerConnectionState) -> String {
        var lines: [String] = []

        if puckState.is_present {
            lines.append("Puck")
            lines.append("  Name: \(puckState.product_name ?? "Steam Controller puck")")
            lines.append("  PID: \(productIDTitle(for: puckState))")
            lines.append("  Transport: \(puckState.transport ?? "unknown")")
        } else {
            lines.append("Puck: not detected")
        }

        lines.append("")

        if controllerState.controller_is_connected {
            lines.append("Controller")
            lines.append("  Name: \(controllerState.controller_name ?? "connected")")
            lines.append("  Path/id: \(controllerState.controller_path_or_id ?? "unknown")")
        } else {
            lines.append("Controller: not connected")
        }

        return lines.joined(separator: "\n")
    }

    private func infoText(puckState: PuckState, controllerState: ControllerConnectionState) -> String {
        """
        Puck
          Present: \(yesNo(puckState.is_present))
          Vendor ID: \(hexTitle(puckState.vendor_id, width: 4))
          Product ID: \(productIDTitle(for: puckState))
          Product name: \(puckState.product_name ?? "unknown")
          Manufacturer: \(puckState.manufacturer ?? "unknown")
          Transport: \(puckState.transport ?? "unknown")
          Location ID: \(hexTitle(puckState.location_id, width: 8))
          Legacy: \(yesNo(puckState.is_legacy))

        Controller
          Connected: \(yesNo(controllerState.controller_is_connected))
          Name: \(controllerState.controller_name ?? "unknown")
          Path/id: \(controllerState.controller_path_or_id ?? "unknown")
          SDL gamepads: \(controllerState.sdl_gamepad_count)
        """
    }

    private func productIDTitle(for state: PuckState) -> String {
        guard let productID = state.product_id else { return "unknown" }

        let formatted = hexTitle(productID, width: 4)
        if state.is_legacy {
            return "\(formatted) legacy"
        }

        return formatted
    }

    private func hexTitle(_ value: Int?, width: Int) -> String {
        guard let value else { return "unknown" }
        return String(format: "0x%0\(width)x", value)
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}

final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()

        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView() -> NSView {
        let label = NSTextField(labelWithString: "No settings yet.")
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }
}
