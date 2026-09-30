import AppKit

final class PetInteractionController {
    private weak var windowController: PetWindowController?
    private weak var controller: PetController?

    private var mouseDownPoint: NSPoint?
    private var grabAnchor: NSPoint = .zero
    private var isDragging = false

    private let dragThreshold: CGFloat = 3
    private let dragMargin: CGFloat = 8

    init(windowController: PetWindowController, controller: PetController) {
        self.windowController = windowController
        self.controller = controller
    }

    func mouseDown(at event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
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
            vector: CGVector(dx: current.x - mouseDownPoint.x, dy: current.y - mouseDownPoint.y)
        )
    }

    func mouseUp(at event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard isDragging else { return }
        isDragging = false
        controller?.handleDragEnded()
    }
}
