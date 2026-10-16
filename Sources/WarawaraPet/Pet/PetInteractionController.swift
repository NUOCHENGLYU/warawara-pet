import AppKit

final class PetInteractionController {
    private weak var windowController: PetWindowController?
    private weak var controller: PetController?

    private var mouseDownPoint: NSPoint?
    private var grabAnchor: NSPoint = .zero
    private var isDragging = false

    private var previousGlobalPoint: CGPoint = .zero

    private let dragThreshold: CGFloat = 3
    private let dragMargin: CGFloat = 8

    /// Fired on a genuine double-click (clickCount == 2) on the pet.
    /// Used by the birthday letter reopen path.
    var onDoubleClick: (() -> Void)?

    init(windowController: PetWindowController, controller: PetController) {
        self.windowController = windowController
        self.controller = controller
    }

    func mouseDown(at event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
        previousGlobalPoint = NSEvent.mouseLocation
        if event.clickCount == 2 {
            // The first click already produced the normal squash; the
            // double-click opens the birthday letter instead of a
            // second squash.
            onDoubleClick?()
            return
        }
        controller?.handleClick()
    }

    func mouseDragged(at event: NSEvent) {
        guard let mouseDownPoint, let windowController else { return }
        let current = event.locationInWindow

        if !isDragging {
            let exceededX = abs(current.x - mouseDownPoint.x) > dragThreshold
            let exceededY = abs(current.y - mouseDownPoint.y) > dragThreshold
            guard exceededX || exceededY else { return }
            isDragging = true
            grabAnchor = current
            // grabAnchor is in view coordinates (the content view sits at
            // the window origin), matching PetMetrics' pet-space convention.
            controller?.handleDragBegan(
                grabVector: PetMetrics.normalizedGrabVector(grabPoint: grabAnchor)
            )
        }

        // Capture the global mouse position BEFORE moving the window so the
        // window's own motion never pollutes the velocity measurement.
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(x: mouse.x - grabAnchor.x, y: mouse.y - grabAnchor.y)
        let target = CGRect(origin: origin, size: windowController.currentFrame.size)
        let visible = ScreenGeometry.visibleFrame(
            containing: mouse,
            candidates: ScreenGeometry.screenVisibleFrames()
        ) ?? ScreenGeometry.visibleFrame(for: target)
        windowController.setWindowFrame(
            ScreenGeometry.clampFrame(target, to: visible, margin: dragMargin),
            animated: false
        )

        controller?.handleDragMoved(
            deltaX: mouse.x - previousGlobalPoint.x,
            deltaY: mouse.y - previousGlobalPoint.y,
            at: event.timestamp
        )
        previousGlobalPoint = mouse
    }

    func mouseUp(at event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard isDragging else { return }
        isDragging = false
        controller?.handleDragEnded()
    }
}
