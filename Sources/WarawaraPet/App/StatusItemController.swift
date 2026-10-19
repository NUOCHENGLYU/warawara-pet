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
        guard let button = item.button else {
            // Creation failed at the AppKit level: the quit button can
            // never appear regardless of menu-bar crowding.
            LifecycleDiagnostics.log("STATUS_ITEM_BUTTON_MISSING")
            statusItem = nil
            return
        }
        if let image = NSImage(
            systemSymbolName: "xmark.circle",
            accessibilityDescription: "Quit WarawaraPet"
        ) {
            button.image = image
        } else {
            // Symbol unavailable (very old SDK fallback): still render
            // a text quit glyph so the button remains usable.
            button.title = "✕"
            LifecycleDiagnostics.log("STATUS_ITEM_SYMBOL_MISSING")
        }
        button.toolTip = "Quit WarawaraPet"
        button.target = self
        button.action = #selector(quitApp)
        statusItem = item
        LifecycleDiagnostics.log("STATUS_ITEM_CREATED", details: "visible=\(item.isVisible)")
        // The menu bar may hide crowded items a moment later; record the
        // settled visibility once so field reports can distinguish
        // "creation failed" from "hidden by the menu bar".
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak item] in
            LifecycleDiagnostics.log("STATUS_ITEM_SETTLED", details: "visible=\(item?.isVisible ?? false)")
        }
    }

    /// True when the status item was created (the process is still the
    /// quit path even if the menu bar currently hides the icon).
    var isCreated: Bool { statusItem != nil }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
