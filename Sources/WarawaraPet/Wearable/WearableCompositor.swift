import Foundation

/// Wearable render state published into the character pipeline. The
/// final gift keeps exactly ONE wearable: the birthday hat.
struct WarawaraWearableState: Equatable {
    var birthdayHat: Bool = false
    /// Crossfade amount (0...1); the controller eases this.
    var hatOpacity: CGFloat = 1

    static let none = WarawaraWearableState()
}

/// The runtime observed by the pet view.
final class WearableRuntime: ObservableObject {
    @Published private(set) var state: WarawaraWearableState = .none

    func update(state: WarawaraWearableState) {
        if self.state != state { self.state = state }
    }
}

/// Birthday-hat-only wearable controller:
/// - October 17 (local calendar), or
/// - an active celebration requests it (first-launch surprise).
/// Crossfades instead of hard switches. No other wearables exist.
final class WearableController {
    private let runtime: WearableRuntime
    private let clock: BirthdayClock
    private var timer: Timer?
    private var opacity: CGFloat = 0

    /// External celebration state (first-launch surprise) can request
    /// the birthday hat outside October 17.
    var celebrationRequestsBirthdayHat = false

    init(
        runtime: WearableRuntime,
        clock: BirthdayClock = SystemBirthdayClock()
    ) {
        self.runtime = runtime
        self.clock = clock
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        let now = clock.now()
        let calendar = clock.calendar
        let target: CGFloat = (celebrationRequestsBirthdayHat
            || BirthdayDateMath.isBirthday(date: now, calendar: calendar)) ? 1 : 0

        let factor: CGFloat = 1 - exp(-0.25 / 0.35)
        opacity += (target - opacity) * factor
        if opacity < 0.02 { opacity = 0 }
        if opacity > 0.98 { opacity = 1 }

        runtime.update(state: WarawaraWearableState(
            birthdayHat: opacity > 0.02,
            hatOpacity: opacity
        ))
    }
}

/// Authoritative birthday-hat registration, computed in POINTS inside
/// the rig's render canvas from the rig's normalized bodyBounds — the
/// hat follows the body through every pose transform.
enum WearableCompositor {

    struct PaintedBox {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    /// Installed Birthday CelFilm v5 hat painting (design-locked).
    static let birthdayHatBox = PaintedBox(x: 198.0 / 1024, y: 91.0 / 1024,
                                           width: 628.0 / 1024, height: 832.0 / 1024)

    struct HeadGeometry: Equatable {
        let topCenter: CGPoint
        let width: CGFloat
    }

    static func headGeometry(
        renderSize: CGSize,
        bodyBounds: CGRect
    ) -> HeadGeometry {
        let bodyW = bodyBounds.width * renderSize.width
        let bodyTopY = bodyBounds.minY * renderSize.height
        let bodyH = bodyBounds.height * renderSize.height
        return HeadGeometry(
            topCenter: CGPoint(
                x: bodyBounds.midX * renderSize.width,
                y: bodyTopY + bodyH * 0.06
            ),
            width: bodyW * 0.52
        )
    }

    /// Hat scale: the brim spans ~0.62 of the body width.
    static func hatScale(bodyBounds: CGRect, renderSize: CGSize, box: PaintedBox) -> CGFloat {
        (bodyBounds.width * renderSize.width * 0.62) / (box.width * 1024)
    }

    /// Hat image center: the brim's bottom edge sits slightly INTO the
    /// head top arc so there is never a gap.
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
}
