import CoreGraphics
import Foundation

/// Wearable render state published into the character pipeline.
struct WarawaraWearableState: Equatable {
    /// The active headwear (nil = bare head). Precedence is resolved by
    /// the controller; the renderer only displays this value.
    var headwear: WearableKind?
    /// The red scarf coexists with any headwear.
    var scarf: Bool = false
    /// Crossfade amounts (0...1); the controller eases these.
    var headwearOpacity: CGFloat = 1
    var scarfOpacity: CGFloat = 1

    static let none = WarawaraWearableState()
}

/// Small motion extras computed by the controller (tassel sway etc.).
struct WearableRenderParameters: Equatable {
    /// Tassel/secondary sway in points (0 = neutral).
    var tasselSway: CGFloat = 0

    static let `default` = WearableRenderParameters()
}

/// Authoritative wearable registration, computed in POINTS inside the
/// rig's render canvas. Everything derives from the rig's normalized
/// bodyBounds + mouth anchor, so accessories follow the body through
/// every pose transform — no window-frame math, no hardcoded screen
/// offsets.
enum WearableCompositor {

    /// Painted content bbox of an asset, normalized canvas (top-left).
    struct PaintedBox {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    static let headphonesBox = PaintedBox(x: 122.0 / 1024, y: 169.0 / 1024,
                                          width: 780.0 / 1024, height: 685.0 / 1024)
    static let christmasHatBox = PaintedBox(x: 127.0 / 1024, y: 198.0 / 1024,
                                            width: 770.0 / 1024, height: 627.0 / 1024)
    static let birthdayHatBox = PaintedBox(x: 198.0 / 1024, y: 91.0 / 1024,
                                           width: 628.0 / 1024, height: 832.0 / 1024)
    static let scarfFrontBox = PaintedBox(x: 127.0 / 1024, y: 345.0 / 1024,
                                          width: 770.0 / 1024, height: 477.0 / 1024)

    /// The character's head/collar landmarks in RENDER POINTS, derived
    /// from the rig's normalized body bounds and mouth anchor.
    struct HeadGeometry: Equatable {
        /// Head top arc center (points).
        let topCenter: CGPoint
        /// Head width (points).
        let width: CGFloat
        /// Ear level center (points) — headphone cup center target.
        let earCenter: CGPoint
        /// Collar level Y (points) — scarf front collar top target.
        let collarY: CGFloat
        /// Mouth anchor Y (points) — the scarf must stay below this.
        let mouthY: CGFloat
    }

    static func headGeometry(
        renderSize: CGSize,
        bodyBounds: CGRect,
        mouthAnchor: CGPoint?
    ) -> HeadGeometry {
        let bodyW = bodyBounds.width * renderSize.width
        let bodyTopY = bodyBounds.minY * renderSize.height
        let bodyH = bodyBounds.height * renderSize.height
        let headWidth = bodyW * 0.52
        let topCenter = CGPoint(
            x: bodyBounds.midX * renderSize.width,
            y: bodyTopY + bodyH * 0.06
        )
        let earCenter = CGPoint(
            x: topCenter.x,
            y: bodyTopY + bodyH * 0.22
        )
        let mouthY = (mouthAnchor?.y ?? (bodyBounds.minY + bodyBounds.height * 0.36))
            * renderSize.height
        let collarY = min(
            max(mouthY + bodyH * 0.055, bodyTopY + bodyH * 0.34),
            bodyTopY + bodyH * 0.48
        )
        return HeadGeometry(
            topCenter: topCenter,
            width: headWidth,
            earCenter: earCenter,
            collarY: collarY,
            mouthY: mouthY
        )
    }

    // MARK: - Canvas scales (points per source pixel)

    /// Headphones: the headset spans ~0.86 of the body width.
    static func headphonesScale(bodyBounds: CGRect, renderSize: CGSize) -> CGFloat {
        (bodyBounds.width * renderSize.width * 0.86) / (headphonesBox.width * 1024)
    }

    /// Hats: the brim spans ~0.62 of the body width.
    static func hatScale(bodyBounds: CGRect, renderSize: CGSize, box: PaintedBox) -> CGFloat {
        (bodyBounds.width * renderSize.width * 0.62) / (box.width * 1024)
    }

    /// Scarf: the collar band spans ~0.92 of the body width.
    static func scarfScale(bodyBounds: CGRect, renderSize: CGSize) -> CGFloat {
        (bodyBounds.width * renderSize.width * 0.92) / (scarfFrontBox.width * 1024)
    }

    // MARK: - Image-center placements (points)

    /// Headphones image center: the painting's cup/band vertical center
    /// (0.633 of the source canvas) lands on the ear level.
    static func headphonesCenter(
        head: HeadGeometry,
        bodyBounds: CGRect,
        renderSize: CGSize
    ) -> CGPoint {
        let scale = headphonesScale(bodyBounds: bodyBounds, renderSize: renderSize)
        let canvasPt = 1024 * scale
        let cupCenterFraction = (442.0 + 854.0) / 2 / 1024
        return CGPoint(
            x: head.earCenter.x,
            y: head.earCenter.y - (cupCenterFraction - 0.5) * canvasPt
        )
    }

    /// Hat image center: the brim's bottom edge (box bottom) sits
    /// slightly INTO the head top arc so there is never a gap.
    static func hatCenter(
        head: HeadGeometry,
        bodyBounds: CGRect,
        renderSize: CGSize,
        box: PaintedBox
    ) -> CGPoint {
        let scale = hatScale(bodyBounds: bodyBounds, renderSize: renderSize, box: box)
        let canvasPt = 1024 * scale
        let brimBottomFraction = box.y + box.height
        let overlap = head.width * 0.10
        return CGPoint(
            x: head.topCenter.x,
            y: head.topCenter.y + overlap - (brimBottomFraction - 0.5) * canvasPt
        )
    }

    /// Scarf image center: the front collar's top edge (front-box top)
    /// sits exactly at the collar level, below the mouth.
    static func scarfCenter(
        bodyBounds: CGRect,
        renderSize: CGSize,
        head: HeadGeometry
    ) -> CGPoint {
        let scale = scarfScale(bodyBounds: bodyBounds, renderSize: renderSize)
        let canvasPt = 1024 * scale
        return CGPoint(
            x: bodyBounds.midX * renderSize.width,
            y: head.collarY - (scarfFrontBox.y - 0.5) * canvasPt
        )
    }

    /// Horizontal shift applied to headwear when the head yaws (the
    /// accessories ride the accepted 2.5D face transform).
    static func yawShift(yawDegrees: CGFloat, renderSize: CGSize) -> CGFloat {
        guard abs(yawDegrees) > 0.01 else { return 0 }
        let normalized = min(max(yawDegrees / WarawaraTurnGeometry.maxYawDegrees, -1), 1)
        return normalized * renderSize.width * 0.045
    }
}
