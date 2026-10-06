import AppKit

final class PetInteractionController {
    private weak var windowController: PetWindowController?
    private weak var controller: PetController?

    private var mouseDownPoint: NSPoint?
    private var grabAnchor: NSPoint = .zero
    private var isDragging = false

    private var tiltEstimator = TiltEstimator()
    private var previousGlobalPoint: CGPoint = .zero

    private let dragThreshold: CGFloat = 3
    private let dragMargin: CGFloat = 8

    init(windowController: PetWindowController, controller: PetController) {
        self.windowController = windowController
        self.controller = controller
    }

    func mouseDown(at event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
        previousGlobalPoint = NSEvent.mouseLocation
        tiltEstimator.reset()
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
            controller?.handleDragBegan()
        }

        // Capture the global mouse position BEFORE moving the window, then
        // derive horizontal velocity from consecutive global positions so
        // window motion itself does not pollute the measurement.
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

        tiltEstimator.update(deltaX: mouse.x - previousGlobalPoint.x, at: event.timestamp)
        previousGlobalPoint = mouse
        controller?.handleDragMoved(tilt: tiltEstimator.tilt)
    }

    func mouseUp(at event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard isDragging else { return }
        isDragging = false
        controller?.handleDragEnded()
    }
}
