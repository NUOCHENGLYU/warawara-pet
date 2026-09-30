import AppKit
import SwiftUI

final class PetHostingView: NSHostingView<PetView> {
    var contextMenuProvider: (() -> NSMenu)?

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
