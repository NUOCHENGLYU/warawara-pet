import CoreGraphics
import Foundation

/// Semantic world anchors derived from the main pet's WINDOW frame in
/// AppKit screen coordinates (bottom-left origin). Every event prop is
/// placed through these anchors — never via a generic corner fallback.
struct EventAnchorSystem {
    let petFrame: CGRect

    init(petFrame: CGRect) {
        self.petFrame = petFrame
    }

    /// Character body footprint inside the pet window (shared with the
    /// birthday layout definition — one source of truth).
    var bodyRect: CGRect { BirthdayPropLayout.petBodyRect(petFrame: petFrame) }

    /// Front-center of the body, slightly above the resting baseline:
    /// the catch/hold point for held props (hongbao).
    var handFront: CGPoint {
        CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.52)
    }

    /// Head-center of the body (attention targets derive from here).
    var headCenter: CGPoint {
        CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.86)
    }

    /// Just above the head (entry point for falling props, umbrella
    /// canopy position).
    var aboveHead: CGPoint {
        CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height + 36)
    }

    /// Ground beside the body (right side, resting baseline): calendar,
    /// gift, umbrella reach target.
    var groundBesidePet: CGPoint {
        CGPoint(x: bodyRect.maxX + 24, y: bodyRect.minY + 8)
    }

    /// Left ground point (sprout).
    var nearLeftFoot: CGPoint {
        CGPoint(x: bodyRect.minX - 14, y: bodyRect.minY + 4)
    }

    /// Right ground point (cocoa).
    var nearRightFoot: CGPoint {
        CGPoint(x: bodyRect.maxX - 4, y: bodyRect.minY + 4)
    }

    /// Umbrella handle grip: slightly in front of the hand anchor.
    var umbrellaGrip: CGPoint {
        CGPoint(x: handFront.x + 16, y: handFront.y - 10)
    }
}

/// Normalized painted-content bounds for every production prop PNG
/// (alpha bboxes from the artist handoff manifests, fractions of the
/// 1024 canvas). Drives clipping-safe panel sizing and true content
/// centering.
struct PropContentMetrics {
    /// Normalized bbox within the canvas, 0...1 each axis.
    let bbox: CGRect

    var contentCenterOffset: CGPoint {
        CGPoint(
            x: bbox.midX - 0.5,
            y: bbox.midY - 0.5
        )
    }

    static let v1: [String: CGRect] = [
        "cny_lantern.png": CGRect(x: 207.0 / 1024, y: 69.0 / 1024, width: 610.0 / 1024, height: 898.0 / 1024),
        "cny_hongbao.png": CGRect(x: 115.0 / 1024, y: 258.0 / 1024, width: 794.0 / 1024, height: 529.0 / 1024),
        "cny_plum_branch.png": CGRect(x: 76.0 / 1024, y: 42.0 / 1024, width: 894.0 / 1024, height: 947.0 / 1024),
        "cny_firecracker_hanging.png": CGRect(x: 301.0 / 1024, y: 29.0 / 1024, width: 453.0 / 1024, height: 964.0 / 1024),
        "xmas_wreath.png": CGRect(x: 81.0 / 1024, y: 125.0 / 1024, width: 868.0 / 1024, height: 796.0 / 1024),
        "xmas_gift.png": CGRect(x: 134.0 / 1024, y: 174.0 / 1024, width: 772.0 / 1024, height: 760.0 / 1024),
        "newyear_calendar_jan1.png": CGRect(x: 152.0 / 1024, y: 181.0 / 1024, width: 745.0 / 1024, height: 726.0 / 1024),
        "newyear_party_popper.png": CGRect(x: 199.0 / 1024, y: 91.0 / 1024, width: 784.0 / 1024, height: 819.0 / 1024),
        "daily_umbrella.png": CGRect(x: 69.0 / 1024, y: 69.0 / 1024, width: 887.0 / 1024, height: 885.0 / 1024),
        "daily_hot_cocoa.png": CGRect(x: 164.0 / 1024, y: 57.0 / 1024, width: 778.0 / 1024, height: 908.0 / 1024),
        "daily_sprout.png": CGRect(x: 273.0 / 1024, y: 262.0 / 1024, width: 479.0 / 1024, height: 647.0 / 1024),
        "daily_paper_airplane.png": CGRect(x: 76.0 / 1024, y: 258.0 / 1024, width: 867.0 / 1024, height: 518.0 / 1024)
    ]

    static let v3: [String: CGRect] = [
        "cny_hongbao_open.png": CGRect(x: 46.0 / 1024, y: 74.0 / 1024, width: 967.0 / 1024, height: 931.0 / 1024),
        "cny_hongbao_note.png": CGRect(x: 343.0 / 1024, y: 157.0 / 1024, width: 322.0 / 1024, height: 258.0 / 1024),
        "xmas_gift_open_base.png": CGRect(x: 132.0 / 1024, y: 464.0 / 1024, width: 765.0 / 1024, height: 481.0 / 1024),
        "xmas_gift_lid.png": CGRect(x: 132.0 / 1024, y: 175.0 / 1024, width: 776.0 / 1024, height: 419.0 / 1024),
        "xmas_gift_open.png": CGRect(x: 132.0 / 1024, y: 115.0 / 1024, width: 867.0 / 1024, height: 830.0 / 1024),
        "daily_umbrella_closed.png": CGRect(x: 461.0 / 1024, y: 111.0 / 1024, width: 194.0 / 1024, height: 845.0 / 1024),
        "rain_drops_overlay.png": CGRect(x: 115.0 / 1024, y: 85.0 / 1024, width: 800.0 / 1024, height: 743.0 / 1024),
        "paper_airplane_trail.png": CGRect(x: 104.0 / 1024, y: 415.0 / 1024, width: 776.0 / 1024, height: 193.0 / 1024),
        "newyear_confetti_overlay.png": CGRect(x: 134.0 / 1024, y: 206.0 / 1024, width: 792.0 / 1024, height: 635.0 / 1024)
    ]

    static func metrics(for asset: String) -> PropContentMetrics? {
        if let bbox = v1[asset] { return PropContentMetrics(bbox: bbox) }
        if let bbox = v3[asset] { return PropContentMetrics(bbox: bbox) }
        return nil
    }
}

/// Pure per-kind scene geometry: content extents, panel sizing, contact
/// anchoring, and attention directions. Deterministic and unit-tested;
/// the presenter only maps the results onto real NSPanels.
enum SeasonalSceneMath {
    /// Layout spec: how each kind's decorations sit relative to the
    /// primary content center (points, scaled by displayPoints/base).
    struct Decoration {
        let asset: String
        let dxFraction: CGFloat
        let dyFraction: CGFloat
        let sizeFraction: CGFloat
    }

    /// Per-kind display + decoration layout (single source of truth).
    static func decorations(for kind: SeasonalEventKind) -> [Decoration] {
        switch kind {
        case .cny:
            return [
                Decoration(asset: "cny_lantern.png", dxFraction: 0.62, dyFraction: -0.52, sizeFraction: 0.9),
                Decoration(asset: "cny_plum_branch.png", dxFraction: -0.62, dyFraction: -0.42, sizeFraction: 0.9),
                Decoration(asset: "cny_firecracker_hanging.png", dxFraction: -0.5, dyFraction: 0.55, sizeFraction: 0.95)
            ]
        case .christmas:
            return [
                Decoration(asset: "xmas_wreath.png", dxFraction: 0.7, dyFraction: -0.55, sizeFraction: 0.95)
            ]
        case .newYear:
            return [
                Decoration(asset: "newyear_party_popper.png", dxFraction: 0.75, dyFraction: -0.3, sizeFraction: 0.85)
            ]
        case .umbrella, .hotCocoa, .sprout, .paperAirplane:
            return []
        }
    }

    /// Where the primary prop's semantic CONTACT point sits relative to
    /// the drawn content center (fraction of content size; y up).
    /// 0,0 = content center; -0.5 = bottom edge; +0.5 = top edge.
    static func contactAnchor(for kind: SeasonalEventKind) -> CGPoint {
        switch kind {
        case .cny:
            return CGPoint(x: 0, y: 0)          // held envelope: center
        case .christmas:
            return CGPoint(x: 0, y: -0.5)       // gift rests on the ground point
        case .newYear:
            return CGPoint(x: 0, y: -0.5)       // calendar sits on the baseline
        case .umbrella:
            return CGPoint(x: 0.06, y: -0.45)   // handle near grip anchor
        case .hotCocoa:
            return CGPoint(x: 0, y: -0.5)       // mug rests on the ground
        case .sprout:
            return CGPoint(x: 0, y: -0.5)       // sprout grows from the ground
        case .paperAirplane:
            return CGPoint(x: 0, y: 0)          // flight path tracks the plane center
        }
    }

    /// The drawn CONTENT size (points) for the primary asset at its
    /// display size.
    static func contentSize(for kind: SeasonalEventKind) -> CGSize {
        guard let metrics = PropContentMetrics.metrics(for: kind.primaryAsset) else {
            return CGSize(width: kind.primaryDisplayPoints, height: kind.primaryDisplayPoints)
        }
        return CGSize(
            width: kind.primaryDisplayPoints * metrics.bbox.width,
            height: kind.primaryDisplayPoints * metrics.bbox.height
        )
    }

    /// Panel size: union of the primary content (including its contact
    /// offset inside the panel) and every decoration extent plus a
    /// safety margin — the window can never clip drawn content (at rest
    /// scale 1 and arrival scale ~0.92).
    static func panelSize(for kind: SeasonalEventKind) -> CGSize {
        let content = contentSize(for: kind)
        let contactOffset = contentOffset(for: kind)
        var minX: CGFloat = contactOffset.width - content.width / 2
        var maxX: CGFloat = contactOffset.width + content.width / 2
        var minY: CGFloat = contactOffset.height - content.height / 2
        var maxY: CGFloat = contactOffset.height + content.height / 2
        for deco in decorations(for: kind) {
            let size = kind.primaryDisplayPoints * deco.sizeFraction
            let cx = contactOffset.width + deco.dxFraction * kind.primaryDisplayPoints
            let cy = contactOffset.height + deco.dyFraction * kind.primaryDisplayPoints
            minX = min(minX, cx - size / 2)
            maxX = max(maxX, cx + size / 2)
            minY = min(minY, cy - size / 2)
            maxY = max(maxY, cy + size / 2)
        }
        // Extra headroom for interactions: lid lift, note rise, descent
        // overshoot, arc lift — per-kind.
        let interactionHeadroom: CGFloat = switch kind {
        case .cny, .christmas: 26
        case .umbrella: 12
        case .paperAirplane: 34
        default: 10
        }
        let margin: CGFloat = 14
        let width = maxX - minX + 2 * (margin + interactionHeadroom)
        let height = maxY - minY + 2 * (margin + interactionHeadroom)
        return CGSize(width: max(width, 90), height: max(height, 90))
    }

    /// Panel ORIGIN that places the primary content's CONTACT point
    /// exactly on the world anchor (the panel is centered on the contact
    /// point, corrected by the content-center offset).
    static func origin(
        anchoredAt anchor: CGPoint,
        kind: SeasonalEventKind
    ) -> CGPoint {
        let size = panelSize(for: kind)
        return CGPoint(
            x: anchor.x - size.width / 2,
            y: anchor.y - size.height / 2
        )
    }

    /// Clamps a panel origin into the visible frame (translation only —
    /// no scaling, no lower-left corner snap: the pet's own screen is
    /// always respected).
    static func clampedOrigin(
        _ origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX + 4), max(visibleFrame.minX + 4, visibleFrame.maxX - panelSize.width - 4)),
            y: min(max(origin.y, visibleFrame.minY + 4), max(visibleFrame.minY + 4, visibleFrame.maxY - panelSize.height - 4))
        )
    }

    /// SwiftUI offset (y-down) applied to the primary IMAGE so that the
    /// prop's semantic CONTACT point lands exactly on the panel center
    /// (which the presenter places on the world anchor). Corrects for
    /// both the contact anchor and the painted-content offset inside the
    /// 1024 canvas — the true fix for content drifting toward corners.
    static func contentOffset(
        asset: String,
        contact: CGPoint,
        displayPoints: CGFloat
    ) -> CGSize {
        guard let metrics = PropContentMetrics.metrics(for: asset) else {
            return CGSize(
                width: -contact.x * displayPoints,
                height: contact.y * displayPoints
            )
        }
        let bbox = metrics.bbox
        let d = displayPoints
        return CGSize(
            width: -d * (bbox.width * (0.5 + contact.x) + bbox.minX),
            height: -d * (1 - bbox.minY - bbox.height / 2 - contact.y * bbox.height)
        )
    }

    static func contentOffset(for kind: SeasonalEventKind) -> CGSize {
        contentOffset(
            asset: kind.primaryAsset,
            contact: contactAnchor(for: kind),
            displayPoints: kind.primaryDisplayPoints
        )
    }

    /// The primary painted-content rect in PANEL coordinates (origin at
    /// the panel center — y-down SwiftUI convention). Used by tests and
    /// panel sizing to prove nothing is clipped.
    static func contentRectInPanel(for kind: SeasonalEventKind) -> CGRect {
        let offset = contentOffset(for: kind)
        let content = contentSize(for: kind)
        guard let metrics = PropContentMetrics.metrics(for: kind.primaryAsset) else {
            return CGRect(
                x: offset.width - content.width / 2,
                y: offset.height - content.height / 2,
                width: content.width, height: content.height
            )
        }
        let bbox = metrics.bbox
        let d = kind.primaryDisplayPoints
        return CGRect(
            x: offset.width + bbox.minX * d,
            y: offset.height + (1 - bbox.minY - bbox.height) * d,
            width: content.width,
            height: content.height
        )
    }

    /// Attention direction from the pet body center to a world target
    /// (up-positive, matches the accepted 2.5D gaze convention).
    static func attentionDirection(
        petFrame: CGRect,
        target: CGPoint
    ) -> CGVector {
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        return EventAttentionMath.direction(
            from: CGPoint(x: body.midX, y: body.midY),
            to: target
        )
    }
}
