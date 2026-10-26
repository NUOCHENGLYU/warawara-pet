import AppKit
import SwiftUI

// MARK: - Metrics

/// Window-space layout for the bottle form. The official v3 art is a
/// full-canvas illustration; the painted bottle maps onto a 163 pt
/// envelope bottom-anchored at the same baseline as the Warawara body,
/// so the morph never clips at the window top.
enum BottleMetrics {
    /// Procedural fallback pieces (assets missing).
    static let glassWidth: CGFloat = 104
    /// Body glass height: the rig body height (118) times the morph
    /// squash (1.06).
    static let glassHeight: CGFloat = 118 * 1.06
    static let neckWidth: CGFloat = 26
    static let neckHeight: CGFloat = 20
    static let rimWidth: CGFloat = 30
    static let rimHeight: CGFloat = 4
    static let corkWidth: CGFloat = 20
    static let corkHeight: CGFloat = 9
    static let corkLift: CGFloat = 8
    static let paperWidth: CGFloat = 36
    static let paperHeight: CGFloat = 52
    /// Sway and bob slack kept inside the window top.
    static let swayExtra: CGFloat = 3
    static let bobExtra: CGFloat = 3
    /// Total height of the procedural front layer (rim + neck + cork +
    /// lift), bottom-anchored at the glass top.
    static var extrasContainerHeight: CGFloat {
        rimHeight + neckHeight + corkHeight + corkLift
    }

    // Official art layout (Ghibli Minimal v3).
    /// Painted bottle envelope height in window points.
    static let artHeight: CGFloat = 163
    /// The unread bottle's painted content width at that height
    /// (708 / 908 of the canvas, scaled) — the common frame width.
    static let artWidth: CGFloat = 127.1
    /// Vertical anchor: the bottle's bottom edge (painted content) sits
    /// on the Warawara body's bottom line.
    static var artBottomY: CGFloat {
        PetMetrics.visualCenter.y + glassHeight / 2
    }
    /// Top edge of the art envelope at rest.
    static var artTopY: CGFloat {
        artBottomY - artHeight
    }

    static func artTopReach() -> CGFloat {
        artHeight - glassHeight / 2 + swayExtra + bobExtra
    }

    static func proceduralTopReach() -> CGFloat {
        glassHeight / 2 + extrasContainerHeight + swayExtra + bobExtra
    }

    /// The bottle must never be clipped by the window top — the
    /// invariant guards BOTH the art path and the procedural fallback.
    static func fitsInWindow() -> Bool {
        max(artTopReach(), proceduralTopReach()) <= PetMetrics.visualCenter.y
    }
}

// MARK: - Pure morph geometry

/// The continuous morph between the Warawara silhouette and the bottle
/// silhouette: ONE revealed region (a bottom-anchored rounded rect)
/// whose size, corner radius and inner image scale all interpolate with
/// the eased morph progress. The bottle art is ALWAYS masked by this
/// region — it grows out of the blob instead of crossfading in.
enum BottleMorphGeometry {
    /// Revealed region width: the rig body width grows into the full
    /// bottle width.
    static func revealedWidth(progress: Double, blobWidth: CGFloat) -> CGFloat {
        let t = CGFloat(smoothstep(progress, 0.05, 0.9))
        return mix(blobWidth, BottleMetrics.artWidth, t)
    }

    /// Revealed region height: the body height stretches into the full
    /// bottle envelope (the cork emerges as the top grows).
    static func revealedHeight(progress: Double) -> CGFloat {
        let t = CGFloat(smoothstep(progress, 0.1, 1.0))
        return mix(PetMetrics.blobHeight, BottleMetrics.artHeight, t)
    }

    /// The image inside the reveal stretches with the revealed height —
    /// the bottle appears compressed inside the blob first, then grows.
    static func artScale(progress: Double) -> CGFloat {
        revealedHeight(progress: progress) / BottleMetrics.artHeight
    }

    /// Reveal corner radius: full capsule (blob) at the start, shallow
    /// bottle corners at the end (the neck/shoulders open up).
    static func cornerRadius(progress: Double, width: CGFloat) -> CGFloat {
        let t = CGFloat(smoothstep(progress, 0.05, 0.85))
        return mix(width / 2, width * 0.10, t)
    }

    /// The art fades in quickly while the body raster fades out
    /// (0.15...0.75) — the reveal mask keeps the shapes aligned so this
    /// reads as a material change, not a crossfade.
    static func handoverOpacity(progress: Double) -> CGFloat {
        CGFloat(smoothstep(progress, 0.04, 0.28))
    }

    /// During the revert, the empty bottle (idle) replaces the unread
    /// bottle: 0 = unread only, 1 = idle only.
    static func revertBlend(progress: Double) -> CGFloat {
        // progress runs 1 -> 0 during transformingBack.
        CGFloat(1 - smoothstep(progress, 0.6, 0.9))
    }

    /// Unread -> opening state crossfade driven by the opening progress.
    static func openingBlend(openingProgress: Double) -> CGFloat {
        CGFloat(smoothstep(openingProgress, 0.15, 1.0))
    }

    /// Two-stage body choreography (expression system): compress first,
    /// then stretch into the bottle.
    static func compressAmount(progress: Double) -> CGFloat {
        let p = CGFloat(min(max(progress, 0), 1))
        return sin(.pi * min(p / 0.45, 1))
    }

    static func stretchAmount(progress: Double) -> CGFloat {
        CGFloat(smoothstep(progress, 0.5, 0.95))
    }

    /// Face fade: eyes + mouth dissolve between these progress bounds.
    static func faceOpacity(progress: Double) -> CGFloat {
        CGFloat(1 - smoothstep(progress, 0.2, 0.6))
    }

    /// Body raster handover (used by the expression mapper).
    static func bodyHandoverOpacity(progress: Double) -> CGFloat {
        CGFloat(1 - smoothstep(progress, 0.15, 0.75))
    }

    static func smoothstep(_ x: Double, _ edge0: Double, _ edge1: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * min(max(t, 0), 1)
    }
}

/// The reveal mask: a bottom-anchored rounded rect of the interpolated
/// size, inside the square art frame.
struct BottleMorphMaskShape: Shape {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var bounds = CGRect(
            x: rect.midX - width / 2,
            y: rect.maxY - height,
            width: width,
            height: height
        )
        if bounds.minY < rect.minY {
            bounds.origin.y = rect.minY
            bounds.size.height = rect.height
        }
        return Path(
            roundedRect: bounds,
            cornerRadius: min(cornerRadius, min(width, height) / 2)
        )
    }
}

// MARK: - Art-backed bottle rendering

/// Renders ONE bottle state image through the morph geometry: the image
/// is scaled with the revealed height and masked by the revealed
/// region, bottom-anchored on the body baseline.
struct BottleArtStateView: View {
    let image: NSImage
    let progress: Double
    let blobWidth: CGFloat
    /// Crossfade weight of this layer (0...1) — used to blend between
    /// state images at the SAME silhouette.
    let blend: Double

    private var scale: CGFloat { BottleMorphGeometry.artScale(progress: progress) }
    private var width: CGFloat { BottleMorphGeometry.revealedWidth(progress: progress, blobWidth: blobWidth) }
    private var height: CGFloat { BottleMorphGeometry.revealedHeight(progress: progress) }
    private var radius: CGFloat { BottleMorphGeometry.cornerRadius(progress: progress, width: width) }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: BottleMetrics.artHeight, height: BottleMetrics.artHeight)
            .scaleEffect(scale, anchor: .bottom)
            .mask(
                BottleMorphMaskShape(width: width, height: height, cornerRadius: radius)
                    .frame(
                        width: BottleMetrics.artHeight,
                        height: BottleMetrics.artHeight,
                        alignment: .bottom
                    )
            )
            .opacity(BottleMorphGeometry.handoverOpacity(progress: progress) * blend)
    }
}

/// Chooses the presentation mode (testable without SwiftUI):
/// - `.poofArt`: full v3 art + poof smoke — the formal transition
///   (hop -> smoke -> hidden swap -> landing);
/// - `.revealArt`: v3 art without smoke — the geometric-reveal
///   fallback (never used when the poof pack is present);
/// - `.procedural`: procedural placeholder when the v3 art is missing.
enum BottleVisualContent: Equatable {
    case poofArt
    case revealArt
    case procedural

    static func resolve(store: BottleMailArtStore) -> BottleVisualContent {
        guard store.hasBottleArt else { return .procedural }
        return store.hasPoofAssets ? .poofArt : .revealArt
    }
}

/// The complete bottle presentation inside the pet window, driven by
/// the visual coordinator. The formal path (poof) only shows the
/// bottle once the hidden swap has happened; the geometric reveal and
/// the procedural placeholder remain as internal fallbacks.
struct BottleArtOverlayView: View {
    @ObservedObject var visual: BottleVisualCoordinator
    let store: BottleMailArtStore

    /// The rig's actual body width in points (the reveal fallback
    /// starts at the body silhouette, not a hardcoded blob).
    static func rigBodyWidth() -> CGFloat {
        guard let rig = WarawaraRigLoader.shared.rig,
              let size = WarawaraExpressionDriver.renderSize(
                  rig: rig, targetBodyHeight: PetMetrics.blobHeight
              ) else {
            return PetMetrics.blobWidth
        }
        return max(rig.bodyBounds.width * size.width, 1)
    }

    var body: some View {
        ZStack {
            switch BottleVisualContent.resolve(store: store) {
            case .poofArt:
                poofArtComposition
            case .revealArt:
                revealArtComposition
            case .procedural:
                proceduralComposition
            }
        }
        .frame(width: BottleMetrics.artWidth, height: BottleMetrics.artHeight)
        .position(
            x: PetMetrics.visualCenter.x,
            y: BottleMetrics.artBottomY - BottleMetrics.artHeight / 2
        )
    }

    // MARK: Poof composition (formal)

    @ViewBuilder
    private var poofArtComposition: some View {
        // Only visible AFTER the hidden swap — never overlapping the
        // Warawara silhouette.
        if visual.formProgress >= 1 {
            switch visual.visualState {
            case .normal:
                EmptyView()
            case .transformingToBottle, .bottleIdle, .suspended:
                if let unread = store.bottleUnread {
                    BottlePoofArtView(image: unread)
                }
            case .bottleOpening:
                if let unread = store.bottleUnread, let opening = store.bottleOpening {
                    let blend = BottleMorphGeometry.openingBlend(openingProgress: visual.openingProgress)
                    BottlePoofArtView(image: unread)
                        .opacity(1 - blend)
                    BottlePoofArtView(image: opening)
                        .opacity(blend)
                }
            case .reading:
                if let opening = store.bottleOpening {
                    BottlePoofArtView(image: opening)
                }
            case .transformingBack:
                if let unread = store.bottleUnread, let idle = store.bottleIdle {
                    let blend = BottleMorphGeometry.revertBlend(progress: visual.morphProgress)
                    BottlePoofArtView(image: unread)
                        .opacity(1 - blend)
                    BottlePoofArtView(image: idle)
                        .opacity(blend)
                } else if let idle = store.bottleIdle {
                    BottlePoofArtView(image: idle)
                }
            }
        }
    }

    // MARK: Geometric reveal (fallback when the poof pack is missing)

    @ViewBuilder
    private var revealArtComposition: some View {
        let progress = visual.morphProgress
        let blobWidth = Self.rigBodyWidth()
        switch visual.visualState {
        case .normal:
            EmptyView()
        case .transformingToBottle, .bottleIdle, .suspended:
            // Suspended mid-morph keeps the frozen silhouette visible.
            if let unread = store.bottleUnread {
                BottleArtStateView(image: unread, progress: progress, blobWidth: blobWidth, blend: 1)
            }
        case .bottleOpening:
            if let unread = store.bottleUnread, let opening = store.bottleOpening {
                let blend = BottleMorphGeometry.openingBlend(openingProgress: visual.openingProgress)
                BottleArtStateView(image: unread, progress: progress, blobWidth: blobWidth, blend: 1 - blend)
                BottleArtStateView(image: opening, progress: progress, blobWidth: blobWidth, blend: blend)
            }
        case .reading:
            if let opening = store.bottleOpening {
                BottleArtStateView(image: opening, progress: progress, blobWidth: blobWidth, blend: 1)
            }
        case .transformingBack:
            if let unread = store.bottleUnread, let idle = store.bottleIdle {
                let blend = BottleMorphGeometry.revertBlend(progress: progress)
                BottleArtStateView(image: unread, progress: progress, blobWidth: blobWidth, blend: 1 - blend)
                BottleArtStateView(image: idle, progress: progress, blobWidth: blobWidth, blend: blend)
            } else if let idle = store.bottleIdle {
                BottleArtStateView(image: idle, progress: progress, blobWidth: blobWidth, blend: 1)
            }
        }
    }

    // MARK: Procedural fallback (art missing)

    @ViewBuilder
    private var proceduralComposition: some View {
        let progress = visual.morphProgress
        ZStack {
            BottleGlassBodyView(progress: progress)
                .position(
                    x: BottleMetrics.artWidth / 2,
                    y: BottleMetrics.artHeight - BottleMetrics.glassHeight / 2
                )
            BottleExtrasView(progress: progress, openingProgress: visual.openingProgress)
                .position(
                    x: BottleMetrics.artWidth / 2,
                    y: BottleMetrics.artHeight
                        - BottleMetrics.glassHeight
                        - BottleMetrics.extrasContainerHeight / 2
                )
        }
    }
}

// MARK: - Procedural placeholder (fallback only)

/// The translucent glass body, drawn BEHIND the rig body. The rig body
/// fades out through `bodyOpacity` while this fades in. Used ONLY when
/// the v3 art cannot load.
struct BottleGlassBodyView: View {
    /// Eased morph progress 0...1.
    let progress: Double

    private var glassOpacity: Double {
        let ramp = min(max((progress - 0.15) / 0.6, 0), 1)
        return 0.8 * ramp
    }

    var body: some View {
        BottleGlassShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.76, green: 0.84, blue: 0.91).opacity(0.34),
                        Color(red: 0.66, green: 0.76, blue: 0.86).opacity(0.44)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(BottleGlassShape().stroke(Color(white: 1).opacity(0.5), lineWidth: 1.2))
            .frame(width: BottleMetrics.glassWidth, height: BottleMetrics.glassHeight)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 1).opacity(0.22))
                    .frame(width: 7, height: BottleMetrics.glassHeight * 0.62)
                    .offset(x: 12)
            }
            .opacity(glassOpacity)
    }
}

/// Neck, rim, cork and the rolled paper — drawn IN FRONT of the
/// character so the bottle reads above the body. Fallback only.
struct BottleExtrasView: View {
    let progress: Double
    let openingProgress: Double

    private var extrasOpacity: Double {
        min(max((progress - 0.55) / 0.45, 0), 1)
    }

    private var neckGrow: CGFloat {
        CGFloat(BottleMorphMath.eased(min(max((progress - 0.55) / 0.45, 0), 1)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            neckAndRim
            cork
            paper
        }
        .frame(
            width: BottleMetrics.rimWidth,
            height: BottleMetrics.extrasContainerHeight,
            alignment: .bottom
        )
        .opacity(extrasOpacity)
    }

    private var neckAndRim: some View {
        VStack(spacing: 0) {
            rim
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.81, blue: 0.89).opacity(0.42),
                            Color(red: 0.62, green: 0.73, blue: 0.84).opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(white: 1).opacity(0.5), lineWidth: 1)
                )
                .frame(width: BottleMetrics.neckWidth,
                       height: BottleMetrics.neckHeight * neckGrow)
        }
    }

    private var rim: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(red: 0.62, green: 0.73, blue: 0.84).opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(Color(white: 1).opacity(0.5), lineWidth: 1)
            )
            .frame(width: BottleMetrics.rimWidth, height: BottleMetrics.rimHeight)
    }

    private var cork: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.83, green: 0.70, blue: 0.52), Color(red: 0.70, green: 0.56, blue: 0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: BottleMetrics.corkWidth, height: BottleMetrics.corkHeight)
            .offset(y: -(BottleMetrics.rimHeight + BottleMetrics.neckHeight * neckGrow)
                        + BottleMetrics.corkLift * CGFloat(openingProgress))
    }

    private var paper: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: 0.96, green: 0.93, blue: 0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(white: 0.75), lineWidth: 0.8)
            )
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(red: 0.72, green: 0.45, blue: 0.40).opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(4)
            }
            .frame(
                width: BottleMetrics.paperWidth * CGFloat(0.6 + 0.4 * openingProgress),
                height: BottleMetrics.paperHeight * CGFloat(0.25 + 0.75 * openingProgress)
            )
            .offset(y: -(BottleMetrics.rimHeight + BottleMetrics.neckHeight * neckGrow)
                        - 4 - 0.5 * BottleMetrics.paperHeight
                            * CGFloat(0.25 + 0.75 * openingProgress))
            .opacity(0.35 + 0.65 * openingProgress)
    }
}

/// The glass silhouette for the procedural fallback.
struct BottleGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.72))
        path.addCurve(
            to: CGPoint(x: w * 0.18, y: h * 0.12),
            control1: CGPoint(x: 0, y: h * 0.38),
            control2: CGPoint(x: w * 0.06, y: h * 0.2)
        )
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.12))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.72),
            control1: CGPoint(x: w * 0.94, y: h * 0.2),
            control2: CGPoint(x: w, y: h * 0.38)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.72),
            control: CGPoint(x: w * 0.5, y: h * 1.06)
        )
        path.closeSubpath()
        return path
    }
}
