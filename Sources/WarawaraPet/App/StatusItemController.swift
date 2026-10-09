import AppKit

/// Menu-bar status item that acts as a direct Quit button: a single
/// left-click terminates the app immediately. No NSMenu is created or
/// presented anywhere, because menu tracking made macOS hide the
/// nonactivating pet panel when a menu closed.
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    override init() {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "xmark.circle",
                accessibilityDescription: "Quit WarawaraPet"
            )
            button.toolTip = "Quit WarawaraPet"
            button.target = self
            button.action = #selector(quitApp)
        }
        statusItem = item
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
