import AppKit

enum FrameMath {
    static func initialFrame(
        petSize: CGSize,
        in visibleFrame: CGRect,
        margin: CGFloat = 32
    ) -> CGRect {
        let clampedWidth = min(petSize.width, visibleFrame.width)
        let clampedHeight = min(petSize.height, visibleFrame.height)
        let size = CGSize(width: clampedWidth, height: clampedHeight)

        let minX = visibleFrame.minX
        let minY = visibleFrame.minY
        let maxX = visibleFrame.maxX - clampedWidth
        let maxY = visibleFrame.maxY - clampedHeight

        let desiredX = visibleFrame.maxX - margin - clampedWidth
        let desiredY = visibleFrame.minY + margin

        let x = max(min(desiredX, maxX), minX)
        let y = max(min(desiredY, maxY), minY)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func currentScreenVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }
}
