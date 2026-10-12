import Foundation

/// Companion geometry: the panel canvas is sized to contain the maximum
/// rendered body silhouette (scale + motion stretch + lean) plus uniform
/// padding, so companions never clip. The body is centered in the panel,
/// so panel-center coordinates ARE body-center coordinates for all
/// formation, entry, and exit math.
enum CompanionMetrics {
    static let blobWidth: CGFloat = 60
    static let blobHeight: CGFloat = 74
    static let maxScale: CGFloat = 1.15
    static let maxStretch: CGFloat = 0.14
    static let maxLeanRadians: CGFloat = 0.07
    static let padding: CGFloat = 14

    /// Even canvas size containing the worst-case silhouette + padding.
    static func panelSize(
        maxScale: CGFloat = maxScale,
        maxStretch: CGFloat = maxStretch,
        maxLean: CGFloat = maxLeanRadians,
        padding: CGFloat = padding
    ) -> CGFloat {
        let scaledHeight = blobHeight * maxScale * (1 + maxStretch)
        let scaledWidth = blobWidth * maxScale * (1 + maxStretch)
        let leanExtra = scaledHeight * sin(maxLean) * 0.5
        let needed = max(scaledHeight, scaledWidth) + leanExtra + 2 * padding
        return (ceil(needed / 2) * 2)
    }

    static let size = panelSize()

    /// The rendered body bounds inside the panel: the panel inset by the
    /// uniform padding. Used for staged top-edge exit checks.
    static func bodyFrame(panelFrame: CGRect) -> CGRect {
        panelFrame.insetBy(dx: padding, dy: padding)
    }
}
