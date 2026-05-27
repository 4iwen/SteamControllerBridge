import AppKit

final class DiagnosticsWindowController: NSWindowController {
    private let devicesView = NSTextView()
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
        update(puckStates: [], controllerState: .notConnected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(puckStates: [PuckState], controllerState: ControllerConnectionState) {
        devicesView.string = devicesText(puckStates: puckStates, controllerState: controllerState)
        inputView.string = inputText(controllerState: controllerState)
    }

    private func makeContentView() -> NSView {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        tabView.addTabViewItem(tab(title: "Devices", view: scrollView(for: devicesView)))
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

    private func devicesText(puckStates: [PuckState], controllerState: ControllerConnectionState) -> String {
        var lines: [String] = []

        lines.append("Pucks")
        if puckStates.isEmpty {
            lines.append("  not detected")
        } else {
            for (index, puck) in puckStates.enumerated() {
                lines.append("  \(index + 1). \(puck.product_name ?? "Steam Controller puck")")
                lines.append("     PID: \(productIDTitle(for: puck))")
                lines.append("     Transport: \(puck.transport ?? "unknown")")
                lines.append("     Location: \(hexTitle(puck.location_id, width: 8))")
            }
        }

        lines.append("")
        lines.append("Controllers")
        if controllerState.devices.isEmpty {
            lines.append("  not active")
        } else {
            for (index, controller) in controllerState.devices.enumerated() {
                lines.append("  \(index + 1). \(controller.name)")
                lines.append("     State: \(controller.is_connected ? "active" : "idle")")
                lines.append("     ID: \(controller.device_id)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func inputText(controllerState: ControllerConnectionState) -> String {
        guard !controllerState.devices.isEmpty else {
            return "Controller: not active"
        }

        var lines: [String] = []
        for (index, controller) in controllerState.devices.enumerated() {
            if index > 0 {
                lines.append("")
            }

            lines.append("\(controller.name) (\(controller.is_connected ? "active" : "idle"))")
            lines.append("Axes")
            for key in controller.input_state.axes.keys.sorted() {
                lines.append("  \(key): \(controller.input_state.axes[key] ?? 0)")
            }

            lines.append("")
            lines.append("Buttons")
            for key in controller.input_state.buttons.keys.sorted() {
                lines.append("  \(key): \(pressedTitle(controller.input_state.buttons[key] ?? false))")
            }
        }

        return lines.joined(separator: "\n")
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

    private func pressedTitle(_ value: Bool) -> String {
        value ? "down" : "-"
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
