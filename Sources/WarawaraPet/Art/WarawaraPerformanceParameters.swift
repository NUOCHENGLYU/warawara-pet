import Foundation

/// Mouth styles the rig may provide. Switching styles is always blended
/// (crossfade) by the renderer, never an instant swap.
enum WarawaraMouthStyle: String, CaseIterable, Equatable {
    case soft
    case neutral
    case relaxed
    case open
    case pressed
    case sleepy
}

/// Continuous character-performance parameters. Rendering never branches
/// on a single "state == X" — it consumes these values, which the
/// expression mapper produces as targets and the parameter animator
/// eases toward over time.
struct WarawaraPerformanceParameters: Equatable {
    /// 0 = fully closed, 1 = fully open.
    var eyeOpenness: CGFloat = 1
    /// Gaze direction, signed: -1...1 in each axis (right/up positive).
    var gazeX: CGFloat = 0
    var gazeY: CGFloat = 0
    /// Mouth shape; transitions are crossfaded by the renderer.
    var mouthStyle: WarawaraMouthStyle = .soft
    /// Mouth opening amount on top of the style shape: 0...1.
    var mouthOpenAmount: CGFloat = 0
    /// 0 = fully awake, 1 = fully asleep (drives droop + breathing depth).
    var drowsiness: CGFloat = 0
    /// Click/press intensity: 0...1.
    var pressAmount: CGFloat = 0
    /// Drag intensity: 0...1.
    var dragAmount: CGFloat = 0
    /// Signed drag direction, -1...1 (right/up positive).
    var dragDirectionX: CGFloat = 0
    var dragDirectionY: CGFloat = 0
    /// Body squash factors (1 = neutral). The outer pose pipeline already
    /// applies state-driven squash for hop/clicked/sleep/settle; the
    /// mapper keeps these neutral for those states to avoid double
    /// deformation, and the layered renderer applies them only when the
    /// outer pipeline is identity for the state.
    var bodySquashX: CGFloat = 1
    var bodySquashY: CGFloat = 1
    /// Body lean in radians (internal, face-system level).
    var bodyTilt: CGFloat = 0
    /// Looping phase 0...1 for breathing.
    var breathPhase: CGFloat = 0
    /// Looping phase 0...1 while floating (0 elsewhere).
    var floatPhase: CGFloat = 0

    // Reserved for the limbs layer (next phase). Kept in the model now so
    // future rig layers can consume them without a format change.
    var limbSwingAmount: CGFloat = 0
    var limbLagPhase: CGFloat = 0

    static let neutral = WarawaraPerformanceParameters()

    func clamped() -> WarawaraPerformanceParameters {
        var copy = self
        copy.eyeOpenness = min(max(eyeOpenness, 0), 1)
        copy.gazeX = min(max(gazeX, -1), 1)
        copy.gazeY = min(max(gazeY, -1), 1)
        copy.mouthOpenAmount = min(max(mouthOpenAmount, 0), 1)
        copy.drowsiness = min(max(drowsiness, 0), 1)
        copy.pressAmount = min(max(pressAmount, 0), 1)
        copy.dragAmount = min(max(dragAmount, 0), 1)
        copy.dragDirectionX = min(max(dragDirectionX, -1), 1)
        copy.dragDirectionY = min(max(dragDirectionY, -1), 1)
        copy.bodySquashX = min(max(bodySquashX, 0.5), 2)
        copy.bodySquashY = min(max(bodySquashY, 0.5), 2)
        copy.breathPhase = breathPhase - floor(breathPhase)
        copy.floatPhase = floatPhase - floor(floatPhase)
        copy.limbSwingAmount = min(max(limbSwingAmount, 0), 1)
        return copy
    }

    /// Distance from neutral, used by tests and diagnostics.
    func distance(to other: WarawaraPerformanceParameters) -> CGFloat {
        var total: CGFloat = 0
        total += abs(eyeOpenness - other.eyeOpenness)
        total += abs(gazeX - other.gazeX) + abs(gazeY - other.gazeY)
        total += abs(mouthOpenAmount - other.mouthOpenAmount)
        total += abs(drowsiness - other.drowsiness)
        total += abs(pressAmount - other.pressAmount)
        total += abs(dragAmount - other.dragAmount)
        total += abs(bodySquashX - other.bodySquashX) + abs(bodySquashY - other.bodySquashY)
        total += abs(bodyTilt - other.bodyTilt)
        total += (mouthStyle == other.mouthStyle ? 0 : 1)
        return total
    }
}
