import AppKit

final class PetMotionController {
    private enum Mode {
        case none
        case hop
        case float
        case settle
    }

    private weak var windowController: PetWindowController?
    private var timer: Timer?
    private var startFrame: CGRect = .zero
    private var targetFrame: CGRect = .zero
    private var startTime = Date()
    private var hopParams = HopParameters(height: 0, drift: 0, duration: 1)
    private var floatParams = FloatParameters(height: 0, drift: 0, duration: 1, swayPhase: 0)
    private var mode: Mode = .none
    private var progressHandler: ((CGFloat) -> Void)?
    private var completionHandler: ((CGRect) -> Void)?

    private static let settleDuration: TimeInterval = 0.55
    private static let settleAmplitude: CGFloat = 18

    init(windowController: PetWindowController) {
        self.windowController = windowController
    }

    // Main-thread only. Any previously running motion is cancelled first.
    func startHop(
        from startFrame: CGRect,
        parameters: HopParameters,
        progress: @escaping (CGFloat) -> Void,
        completion: @escaping (CGRect) -> Void
    ) {
        cancelMotion()
        mode = .hop
        self.startFrame = startFrame
        hopParams = parameters
        progressHandler = progress
        completionHandler = completion
        startTimer()
    }

    func startFloat(
        from startFrame: CGRect,
        parameters: FloatParameters,
        progress: @escaping (CGFloat) -> Void,
        completion: @escaping (CGRect) -> Void
    ) {
        cancelMotion()
        mode = .float
        self.startFrame = startFrame
        floatParams = parameters
        progressHandler = progress
        completionHandler = completion
        startTimer()
    }

    /// Settle with an optional gentle descent phase: when `targetFrame`
    /// differs from `startFrame` the window first eases down to the target
    /// (soft landing from a mid-air position), then plays the bounce.
    func startSettle(
        from startFrame: CGRect,
        to targetFrame: CGRect,
        progress: @escaping (CGFloat) -> Void,
        completion: @escaping (CGRect) -> Void
    ) {
        cancelMotion()
        mode = .settle
        self.startFrame = startFrame
        self.targetFrame = targetFrame
        progressHandler = progress
        completionHandler = completion
        startTimer()
    }

    func cancelMotion() {
        timer?.invalidate()
        timer = nil
        progressHandler = nil
        completionHandler = nil
        mode = .none
    }

    private func startTimer() {
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let windowController else {
            cancelMotion()
            return
        }
        let elapsed = Date().timeIntervalSince(startTime)
        switch mode {
        case .hop:
            let duration = hopParams.duration
            let t = CGFloat(min(max(elapsed / duration, 0), 1))
            var frame = startFrame
            frame.origin.x += HopCurve.offsetX(at: t, drift: hopParams.drift)
            frame.origin.y += HopCurve.offsetY(at: t, height: hopParams.height)
            frame = ScreenGeometry.clampFrame(
                frame,
                to: ScreenGeometry.visibleFrame(for: frame),
                margin: 8
            )
            windowController.setWindowFrame(frame, animated: false)
            progressHandler?(t)
            if t >= 1 { finish() }
        case .float:
            let duration = floatParams.duration
            let t = CGFloat(min(max(elapsed / duration, 0), 1))
            let tuning = PersonalityTuning.default
            var frame = startFrame
            frame.origin.x += FloatCurve.offsetX(
                at: t,
                drift: floatParams.drift,
                swayAmplitude: tuning.floatSwayAmplitude,
                swayCycles: FloatCurve.swayCycles(duration: duration, tuning: tuning),
                swayPhase: floatParams.swayPhase
            )
            frame.origin.y += FloatCurve.offsetY(at: t, height: floatParams.height, tuning: tuning)
            frame = ScreenGeometry.clampFrame(
                frame,
                to: ScreenGeometry.visibleFrame(for: frame),
                margin: 8
            )
            windowController.setWindowFrame(frame, animated: false)
            progressHandler?(t)
            if t >= 1 { finish() }
        case .settle:
            let descentDuration = PersonalityTuning.default.floatDescentDuration
            let totalDuration = descentDuration + Self.settleDuration
            let t = CGFloat(min(max(elapsed / totalDuration, 0), 1))
            var frame = startFrame
            if elapsed < descentDuration {
                let d = CGFloat(min(max(elapsed / descentDuration, 0), 1))
                frame.origin.x = DescentCurve.interpolate(
                    at: d, from: startFrame.origin.x, to: targetFrame.origin.x
                )
                frame.origin.y = DescentCurve.interpolate(
                    at: d, from: startFrame.origin.y, to: targetFrame.origin.y
                )
            } else {
                let b = CGFloat(min(max((elapsed - descentDuration) / Self.settleDuration, 0), 1))
                frame.origin.x = targetFrame.origin.x
                frame.origin.y = targetFrame.origin.y
                    + SettleCurve.offsetY(at: b, amplitude: Self.settleAmplitude)
            }
            frame = ScreenGeometry.clampFrame(
                frame,
                to: ScreenGeometry.visibleFrame(for: frame),
                margin: 8
            )
            windowController.setWindowFrame(frame, animated: false)
            progressHandler?(t)
            if t >= 1 { finish() }
        case .none:
            break
        }
    }

    private func finish() {
        let finalFrame = windowController?.currentFrame ?? startFrame
        let completion = completionHandler
        cancelMotion()
        completion?(finalFrame)
    }
}
