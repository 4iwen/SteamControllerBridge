import AppKit

final class DiagnosticsWindowController: NSWindowController {
    private let devicesView = NSTextView()
    private let inputView = NSTextView()
    private let formatter = DiagnosticsTextFormatter()

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
        devicesView.string = formatter.devicesText(puckStates: puckStates, controllerState: controllerState)
        inputView.string = formatter.inputText(controllerState: controllerState)
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
}
