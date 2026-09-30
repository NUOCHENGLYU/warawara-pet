import AppKit
import SwiftUI

final class PetWindowController: NSObject {
    static let petSize = CGSize(width: 160, height: 160)

    private var panel: PetPanel?
    private var hostingView: PetHostingView?

    func showPet() {
        let panel = PetPanel(size: Self.petSize)

        let hostingView = PetHostingView(rootView: PetView())
        hostingView.frame = NSRect(origin: .zero, size: Self.petSize)
        hostingView.contextMenuProvider = { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        }

        panel.contentView = hostingView
        panel.setFrame(
            FrameMath.initialFrame(
                petSize: Self.petSize,
                in: FrameMath.currentScreenVisibleFrame()
            ),
            display: false
        )
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit WarawaraPet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
        return menu
    }
}
