import AppKit
import SwiftUI

final class PetHostingView: NSHostingView<PetView> {
    var contextMenuProvider: (() -> NSMenu)?
    weak var interactionController: PetInteractionController?

    private var hitRegion: EllipseHitRegion?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hitRegion = EllipseHitRegion.petDefault(in: bounds)
    }

    // The pet needs no keyboard input, so this view must never require the
    // panel to become key for input delivery.
    override var needsPanelToBecomeKey: Bool { false }

    // Deliver the first click immediately even though the panel is
    // non-key-capable and the app is not active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitRegion else { return super.hitTest(point) }
        let localPoint: NSPoint
        if let superview {
            localPoint = convert(point, from: superview)
        } else {
            localPoint = point
        }
        guard hitRegion.contains(localPoint) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        interactionController?.mouseDown(at: event)
    }

    override func mouseDragged(with event: NSEvent) {
        interactionController?.mouseDragged(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        interactionController?.mouseUp(at: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
