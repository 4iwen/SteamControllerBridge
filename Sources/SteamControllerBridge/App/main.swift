import AppKit

// hide from the dock since this is supposed to only appear in the menu bar
NSApplication.shared.setActivationPolicy(.accessory)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
