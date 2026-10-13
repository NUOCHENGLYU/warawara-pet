import Foundation

/// Visual states the artwork must cover. Every existing pet state maps to
/// exactly one visual state; companions use the same mapping so main and
/// companion characters always share artwork.
enum WarawaraVisualState: String, CaseIterable, Equatable {
    case idle
    case hop
    case float
    case curious
    case clicked
    case dragged
    case settling
    case sleepy
    case sleeping
    case wake

    static func state(for petState: PetState) -> WarawaraVisualState {
        switch petState {
        case .idle: return .idle
        case .hop: return .hop
        case .float: return .float
        case .curious: return .curious
        case .clicked: return .clicked
        case .dragged: return .dragged
        case .settling: return .settling
        case .sleepy: return .sleepy
        case .sleeping: return .sleeping
        }
    }
}

/// Maps visual states to manifest animation keys and computes frame
/// indices. Pure and deterministic: the same instant always yields the
/// same frame.
enum WarawaraAnimationMapper {
    static func animationKey(for visualState: WarawaraVisualState) -> String {
        visualState.rawValue
    }

    /// Frame index for an animation at the given elapsed time. Looping
    /// animations cycle forever; non-looping animations hold their final
    /// frame.
    static func frameIndex(
        at time: TimeInterval,
        animation: WarawaraSpriteManifest.Animation
    ) -> Int {
        let frameCount = animation.frames.count
        guard frameCount > 1 else { return 0 }
        let duration = max(animation.frameDuration, 0.001)
        let index = Int((max(time, 0) / duration).rounded(.down))
        if animation.loop {
            return index % frameCount
        }
        return min(index, frameCount - 1)
    }

    /// Logical-to-pixel scaling: converts manifest canvas coordinates
    /// into a rendered size for a given target body height.
    static func renderSize(
        canvas: CGSize,
        bodyHeightInCanvas: CGFloat,
        targetBodyHeight: CGFloat
    ) -> CGSize {
        guard bodyHeightInCanvas > 0 else { return canvas }
        let factor = targetBodyHeight / bodyHeightInCanvas
        return CGSize(width: canvas.width * factor, height: canvas.height * factor)
    }
}
