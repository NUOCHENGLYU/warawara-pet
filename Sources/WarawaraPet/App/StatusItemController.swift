import AppKit

/// Owns the menu-bar status item that provides app-wide controls
/// (currently just Quit). Completely independent of PetPanel,
/// PetHostingView, and pet interaction state: opening or closing this
/// menu never touches the pet window.
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    override init() {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "W"
        item.button?.toolTip = "WarawaraPet"

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit WarawaraPet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }
}
