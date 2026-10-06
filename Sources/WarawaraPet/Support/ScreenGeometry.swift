import AppKit

enum ScreenGeometry {
    static func clampFrame(
        _ frame: CGRect,
        to visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let clampedWidth = min(frame.width, visibleFrame.width)
        let clampedHeight = min(frame.height, visibleFrame.height)
        let size = CGSize(width: clampedWidth, height: clampedHeight)

        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = visibleFrame.maxX - clampedWidth - margin
        let maxY = visibleFrame.maxY - clampedHeight - margin

        let x = max(min(frame.origin.x, maxX), minX)
        let y = max(min(frame.origin.y, maxY), minY)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func visibleFrame(
        containing point: CGPoint,
        candidates: [CGRect]
    ) -> CGRect? {
        candidates.first { $0.contains(point) }
    }

    static func screenVisibleFrames() -> [CGRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    static func visibleFrame(for frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return visibleFrame(containing: center, candidates: screenVisibleFrames())
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
    }

    static func restoredFrame(
        savedOrigin: CGPoint,
        petSize: CGSize,
        visibleFrames: [CGRect],
        margin: CGFloat
    ) -> CGRect? {
        let savedFrame = CGRect(origin: savedOrigin, size: petSize)
        for visibleFrame in visibleFrames {
            let safeArea = visibleFrame.insetBy(dx: margin, dy: margin)
            if safeArea.intersects(savedFrame) {
                return clampFrame(savedFrame, to: visibleFrame, margin: margin)
            }
        }
        return nil
    }

    /// Pure restore-vs-default decision: returns the clamped restored frame
    /// when the saved origin is still valid on the current screens,
    /// otherwise the default safe frame.
    static func restoredPositionFrame(
        savedOrigin: CGPoint?,
        petSize: CGSize,
        visibleFrames: [CGRect],
        restoreMargin: CGFloat,
        defaultVisibleFrame: CGRect
    ) -> CGRect {
        if let savedOrigin,
           let restored = restoredFrame(
               savedOrigin: savedOrigin,
               petSize: petSize,
               visibleFrames: visibleFrames,
               margin: restoreMargin
           ) {
            return restored
        }
        return FrameMath.initialFrame(
            petSize: petSize,
            in: defaultVisibleFrame
        )
    }
}
