import CoreGraphics
import Foundation

/// THE authoritative prop render geometry.
///
/// A prop's visual size is the size of its PAINTED CONTENT, not its
/// transparent 1024×1024 canvas. Exactly ONE source-pixel-to-AppKit-point
/// scale exists per asset:
///
///     scale = targetVisibleWidthPt / paintedWidthPx
///     canvasDisplaySizePt = 1024 * scale
///
/// The painted bbox transforms with the same scale — it is never applied
/// twice. All measurements come from the Warawara_Event_Geometry_Audit_v1
/// handoff (alpha≥32 bounds), and all view coordinates here are SwiftUI
/// y-down from top unless noted.
enum PropRenderGeometry {

    /// The pet's actual painted character height in AppKit points —
    /// everything is calibrated against this value.
    static var petHeight: CGFloat { PetMetrics.blobHeight }

    static let canvasPx: CGFloat = 1024
    /// Safety margin between painted content and every clipping boundary.
    static let margin: CGFloat = 12

    struct SourceBox {
        let left: CGFloat
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat

        var width: CGFloat { right - left }
        var height: CGFloat { bottom - top }
    }

    /// Alpha≥32 painted bounds, source pixels (left, top, right, bottom).
    static let boxes: [String: SourceBox] = [
        "cny_firecracker_hanging.png": SourceBox(left: 301, top: 29, right: 754, bottom: 993),
        "cny_hongbao.png": SourceBox(left: 115, top: 258, right: 909, bottom: 787),
        "cny_lantern.png": SourceBox(left: 207, top: 69, right: 817, bottom: 967),
        "cny_plum_branch.png": SourceBox(left: 76, top: 43, right: 970, bottom: 989),
        "daily_hot_cocoa.png": SourceBox(left: 164, top: 57, right: 942, bottom: 965),
        "daily_paper_airplane.png": SourceBox(left: 77, top: 259, right: 943, bottom: 776),
        "daily_sprout.png": SourceBox(left: 273, top: 262, right: 751, bottom: 909),
        "daily_umbrella.png": SourceBox(left: 69, top: 70, right: 955, bottom: 954),
        "newyear_calendar_jan1.png": SourceBox(left: 152, top: 181, right: 897, bottom: 907),
        "newyear_party_popper.png": SourceBox(left: 200, top: 92, right: 982, bottom: 910),
        "xmas_gift.png": SourceBox(left: 134, top: 174, right: 906, bottom: 933),
        "xmas_wreath.png": SourceBox(left: 82, top: 125, right: 949, bottom: 920),
        "cny_hongbao_note.png": SourceBox(left: 343, top: 157, right: 665, bottom: 415),
        "cny_hongbao_open.png": SourceBox(left: 115, top: 74, right: 909, bottom: 787),
        "daily_umbrella_closed.png": SourceBox(left: 461, top: 111, right: 652, bottom: 954),
        "newyear_confetti_overlay.png": SourceBox(left: 134, top: 206, right: 926, bottom: 841),
        "paper_airplane_trail.png": SourceBox(left: 104, top: 415, right: 880, bottom: 608),
        "rain_drops_overlay.png": SourceBox(left: 115, top: 85, right: 915, bottom: 828),
        "xmas_gift_lid.png": SourceBox(left: 134, top: 176, right: 906, bottom: 594),
        "xmas_gift_open.png": SourceBox(left: 137, top: 116, right: 996, bottom: 933),
        "xmas_gift_open_base.png": SourceBox(left: 137, top: 464, right: 894, bottom: 933)
    ]

    /// Desired painted WIDTH as a fraction of the pet height (QA
    /// calibration starting values from the geometry audit).
    static let targetRatios: [String: CGFloat] = [
        "cny_firecracker_hanging.png": 0.52,
        "cny_hongbao.png": 0.68,
        "cny_lantern.png": 0.82,
        "cny_plum_branch.png": 0.98,
        "daily_hot_cocoa.png": 0.67,
        "daily_paper_airplane.png": 0.88,
        "daily_sprout.png": 0.56,
        "daily_umbrella.png": 1.65,
        "newyear_calendar_jan1.png": 0.82,
        "newyear_party_popper.png": 0.63,
        "xmas_gift.png": 0.85,
        "xmas_wreath.png": 0.93,
        "cny_hongbao_note.png": 0.33,
        "cny_hongbao_open.png": 0.68,
        "daily_umbrella_closed.png": 0.35,
        "newyear_confetti_overlay.png": 1.25,
        "paper_airplane_trail.png": 1.1,
        "rain_drops_overlay.png": 1.35,
        "xmas_gift_lid.png": 0.85,
        "xmas_gift_open.png": 0.85,
        "xmas_gift_open_base.png": 0.85
    ]

    // MARK: - The one and only scale

    static func scale(asset: String) -> CGFloat {
        guard let box = boxes[asset] else { return 0.02 }
        let ratio = targetRatios[asset] ?? 0.5
        return ratio * petHeight / box.width
    }

    static func canvasPt(asset: String) -> CGFloat {
        canvasPx * scale(asset: asset)
    }

    static func contentSizePt(asset: String) -> CGSize {
        guard let box = boxes[asset] else { return .zero }
        let s = scale(asset: asset)
        return CGSize(width: box.width * s, height: box.height * s)
    }

    /// Content rect in VIEW coordinates relative to the CANVAS CENTER
    /// (y-down).
    static func contentRectAroundCanvasCenter(asset: String) -> CGRect {
        guard let box = boxes[asset] else { return .zero }
        let s = scale(asset: asset)
        return CGRect(
            x: (box.left - canvasPx / 2) * s,
            y: (box.top - canvasPx / 2) * s,
            width: box.width * s,
            height: box.height * s
        )
    }

    /// Canvas offset (view coords, y-down) that places the content's
    /// fractional point (fx from left 0...1, fy from bottom 0...1) at the
    /// given view point.
    static func canvasOffset(
        asset: String, fx: CGFloat, fy: CGFloat, at point: CGPoint
    ) -> CGSize {
        let rect = contentRectAroundCanvasCenter(asset: asset)
        let px = rect.minX + fx * rect.width
        let py = rect.minY + (1 - fy) * rect.height
        return CGSize(width: point.x - px, height: point.y - py)
    }

    // MARK: - Per-kind contact + layout

    /// The semantic CONTACT point inside the primary content:
    /// (fraction from content left, fraction from content bottom).
    static func contactPoint(for kind: SeasonalEventKind) -> CGPoint {
        switch kind {
        case .cny: return CGPoint(x: 0.5, y: 0.02)         // held envelope: bottom rests in paws
        case .christmas: return CGPoint(x: 0.5, y: 0)      // gift sits on the ground point
        case .newYear: return CGPoint(x: 0.5, y: 0)        // calendar sits on the baseline
        case .umbrella: return CGPoint(x: 0.5, y: 0.05)    // handle at the grip
        case .hotCocoa: return CGPoint(x: 0.5, y: 0)       // mug rests on the ground
        case .sprout: return CGPoint(x: 0.5, y: 0)         // sprout grows from the ground
        case .paperAirplane: return CGPoint(x: 0.5, y: 0.5) // flight path tracks the plane center
        }
    }

    struct Decoration {
        let asset: String
        /// Placement of the decoration center relative to the primary
        /// CONTENT center, as fractions of the primary CONTENT size
        /// (dxFrac positive = right, dyFrac positive = up in world).
        let dxFrac: CGFloat
        let dyFrac: CGFloat
    }

    static func decorations(for kind: SeasonalEventKind) -> [Decoration] {
        switch kind {
        case .cny:
            return [
                Decoration(asset: "cny_lantern.png", dxFrac: 0.62, dyFrac: 0.52),
                Decoration(asset: "cny_plum_branch.png", dxFrac: -0.62, dyFrac: 0.45),
                Decoration(asset: "cny_firecracker_hanging.png", dxFrac: -0.48, dyFrac: -0.62)
            ]
        case .christmas:
            return [Decoration(asset: "xmas_wreath.png", dxFrac: 0.66, dyFrac: 0.8)]
        case .newYear:
            return [Decoration(asset: "newyear_party_popper.png", dxFrac: 0.72, dyFrac: 0.55)]
        case .umbrella, .hotCocoa, .sprout, .paperAirplane:
            return []
        }
    }

    /// The primary asset's content rect in PANEL coordinates with the
    /// CONTACT at (0,0), y-down.
    static func primaryContentRectInPanel(for kind: SeasonalEventKind) -> CGRect {
        let contact = contactPoint(for: kind)
        let size = contentSizePt(asset: kind.primaryAsset)
        return CGRect(
            x: -contact.x * size.width,
            y: -(1 - contact.y) * size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Decoration content rects in the same panel coordinates.
    static func decorationRectsInPanel(for kind: SeasonalEventKind) -> [CGRect] {
        let primary = primaryContentRectInPanel(for: kind)
        let center = CGPoint(x: primary.midX, y: primary.midY)
        return decorations(for: kind).map { deco in
            let size = contentSizePt(asset: deco.asset)
            let c = CGPoint(
                x: center.x + deco.dxFrac * primary.width,
                y: center.y - deco.dyFrac * primary.height
            )
            return CGRect(
                x: c.x - size.width / 2, y: c.y - size.height / 2,
                width: size.width, height: size.height
            )
        }
    }

    /// Gift open-state rects (base + lifted/rotated lid at lidLift 0...1)
    /// in panel coordinates. The base bottom aligns with the closed
    /// gift's bottom; the lid rises from the base's top seam.
    static func giftOpenRectsInPanel(lidLift: CGFloat) -> (base: CGRect, lid: CGRect) {
        let contact = contactPoint(for: .christmas)
        let baseSize = contentSizePt(asset: "xmas_gift_open_base.png")
        let lidSize = contentSizePt(asset: "xmas_gift_lid.png")
        let baseRect = CGRect(
            x: -contact.x * baseSize.width,
            y: -(1 - contact.y) * baseSize.height,
            width: baseSize.width,
            height: baseSize.height
        )
        // Lid sits on the base's top seam with a small overlap; the lift
        // raises it up-right with a gentle rotation.
        let overlap: CGFloat = 6
        let lift = max(min(lidLift, 1), 0)
        let lidRect = CGRect(
            x: baseRect.midX - lidSize.width / 2 + lift * 0.15 * lidSize.width,
            y: baseRect.minY - lidSize.height + overlap - lift * 0.30 * lidSize.height,
            width: lidSize.width,
            height: lidSize.height
        )
        return (baseRect, lidRect)
    }

    /// The plane's trail rect in panel coordinates (drawn behind the
    /// plane, extending left of it).
    static func trailRectInPanel() -> CGRect {
        let planeSize = contentSizePt(asset: "daily_paper_airplane.png")
        let trailSize = contentSizePt(asset: "paper_airplane_trail.png")
        return CGRect(
            x: -planeSize.width * 0.72 - trailSize.width / 2,
            y: -trailSize.height / 2,
            width: trailSize.width,
            height: trailSize.height
        )
    }

    /// Union of every painted element for the kind at the given lid
    /// lift, in panel coordinates (contact at 0,0), rotation-expanded.
    static func contentExtentRect(for kind: SeasonalEventKind, lidLift: CGFloat = 0) -> CGRect {
        var rect = primaryContentRectInPanel(for: kind)
        for decoRect in decorationRectsInPanel(for: kind) {
            rect = rect.union(decoRect)
        }
        if kind == .christmas {
            let open = giftOpenRectsInPanel(lidLift: lidLift)
            rect = rect.union(open.base)
            rect = rect.union(rotatedBounds(of: open.lid, degrees: 10 * lidLift))
        }
        if kind == .paperAirplane {
            rect = rect.union(trailRectInPanel())
        }
        return rect
    }

    /// Bounding box of a rect rotated by `degrees` around its center.
    static func rotatedBounds(of rect: CGRect, degrees: CGFloat) -> CGRect {
        guard abs(degrees) > 0.01 else { return rect }
        let radians = degrees * .pi / 180
        let w = rect.width
        let h = rect.height
        let cw = abs(w * cos(radians)) + abs(h * sin(radians))
        let ch = abs(w * sin(radians)) + abs(h * cos(radians))
        return CGRect(
            x: rect.midX - cw / 2, y: rect.midY - ch / 2,
            width: cw, height: ch
        )
    }

    /// Panel size: content extents + margin on every side.
    static func panelSize(for kind: SeasonalEventKind) -> CGSize {
        let extents = contentExtentRect(for: kind, lidLift: 1)
        return CGSize(
            width: extents.width + 2 * margin,
            height: extents.height + 2 * margin
        )
    }

    /// Panel ORIGIN (screen coords, y-up) that places the CONTACT point
    /// exactly on the world anchor while centering the panel on the
    /// content extents.
    static func panelOrigin(anchor: CGPoint, kind: SeasonalEventKind) -> CGPoint {
        let size = panelSize(for: kind)
        let extents = contentExtentRect(for: kind, lidLift: 1)
        // Panel center in world coords: contact + (extents.midX, -extents.midY)
        // (view y-down flips to screen y-up).
        let centerX = anchor.x + extents.midX
        let centerY = anchor.y - extents.midY
        return CGPoint(
            x: centerX - size.width / 2,
            y: centerY - size.height / 2
        )
    }

    /// The painted content rect of the primary asset in PANEL screen
    /// coordinates (AppKit y-up), given a panel frame: proves the
    /// artwork is fully inside the window.
    static func primaryContentScreenRect(
        panelFrame: CGRect, kind: SeasonalEventKind
    ) -> CGRect {
        let rect = primaryContentRectInPanel(for: kind)
        let panelCenter = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        return CGRect(
            x: panelCenter.x + rect.minX,
            y: panelCenter.y - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
