import AppKit

final class PetInteractionController {
    private weak var windowController: PetWindowController?
    private weak var controller: PetController?

    private var mouseDownPoint: NSPoint?
    private var grabAnchor: NSPoint = .zero
    private var isDragging = false
    /// Bottle mode: the tap decision is deferred to mouse-up so a drag
    /// (movement beyond the threshold) never opens the letter.
    private var interceptOnRelease = false

    private var previousGlobalPoint: CGPoint = .zero

    private let dragThreshold: CGFloat = 3
    private let dragMargin: CGFloat = 8

    /// Fired on a genuine double-click (clickCount == 2) on the pet.
    /// Used by the birthday letter reopen path.
    var onDoubleClick: (() -> Void)?
    /// Set by the app layer (Phase 8C): returns true when the click was
    /// consumed by the bottle form — the letter opens instead of the
    /// click squash, and the birthday double-click must not stack on
    /// top of it.
    var clickInterceptor: (() -> Bool)?

    init(windowController: PetWindowController, controller: PetController) {
        self.windowController = windowController
        self.controller = controller
    }

    func mouseDown(at event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
        interceptOnRelease = false
        previousGlobalPoint = NSEvent.mouseLocation
        if event.clickCount == 2 {
            // The first click already produced the normal squash; the
            // double-click opens the birthday letter instead of a
            // second squash. In bottle form the whole double-click is
            // consumed — the birthday letter must not stack on top of
            // the reading window.
            if clickInterceptor?() == true { return }
            onDoubleClick?()
            return
        }
        if clickInterceptor?() == true {
            // Bottle mode: record the press only. If this turns into a
            // drag, no letter opens; the tap fires on mouse-up.
            interceptOnRelease = true
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
            // Once a drag starts, a deferred bottle tap must not fire.
            interceptOnRelease = false
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
        if isDragging {
            isDragging = false
            controller?.handleDragEnded()
            return
        }
        if interceptOnRelease {
            interceptOnRelease = false
            // Press without drag: perform the bottle tap (open the
            // letter / re-front the reading window).
            _ = clickInterceptor?()
        }
    }
}
