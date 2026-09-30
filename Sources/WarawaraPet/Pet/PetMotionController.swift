import AppKit

final class PetMotionController {
    private enum Mode {
        case none
        case hop
        case settle
    }

    private weak var windowController: PetWindowController?
    private var timer: Timer?
    private var startFrame: CGRect = .zero
    private var startTime = Date()
    private var parameters = HopParameters(height: 0, drift: 0, duration: 1)
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
        self.parameters = parameters
        progressHandler = progress
        completionHandler = completion
        startTimer()
    }

    func startSettle(
        from startFrame: CGRect,
        progress: @escaping (CGFloat) -> Void,
        completion: @escaping (CGRect) -> Void
    ) {
        cancelMotion()
        mode = .settle
        self.startFrame = startFrame
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
            let duration = parameters.duration
            let t = CGFloat(min(max(elapsed / duration, 0), 1))
            var frame = startFrame
            frame.origin.x += HopCurve.offsetX(at: t, drift: parameters.drift)
            frame.origin.y += HopCurve.offsetY(at: t, height: parameters.height)
            frame = ScreenGeometry.clampFrame(
                frame,
                to: ScreenGeometry.visibleFrame(for: frame),
                margin: 8
            )
            windowController.setWindowFrame(frame, animated: false)
            progressHandler?(t)
            if t >= 1 { finish() }
        case .settle:
            let t = CGFloat(min(max(elapsed / Self.settleDuration, 0), 1))
            var frame = startFrame
            frame.origin.y += SettleCurve.offsetY(at: t, amplitude: Self.settleAmplitude)
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
