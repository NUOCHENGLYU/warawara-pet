import AppKit
import SwiftUI

/// Production realization of the meteor event:
/// - ONE pooled, click-through, transparent panel that follows the
///   FIXED world-space trajectory (never attached to the pet window);
/// - continuous 30 Hz attention tracking through the flight;
/// - celebration after the meteor has FULLY disappeared;
/// - exact cleanup: alpha zero, parked off-screen, no residual sprite.
final class MeteorEventPresenter: MeteorEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var controller: MeteorEventController?
    private let store: GiftAssetStore

    private var panel: BirthdayPropPanel?
    private var timer: Timer?
    private var trajectory: MeteorTrajectory?
    private var attentionDirection: CGVector?
    private var cleanupDone = false
    private let viewState = MeteorViewState()

    /// Meteor painted content width in points (~1.35 x pet height — a
    /// real sky object, not a desktop prop).
    private let contentWidth: CGFloat = 150

    init(
        windowController: PetWindowController,
        controller: MeteorEventController,
        store: GiftAssetStore = .shared
    ) {
        self.windowController = windowController
        self.controller = controller
        self.store = store
    }

    var activeVisibleFrame: CGRect {
        ScreenGeometry.visibleFrame(for: windowController?.currentFrame ?? .zero)
    }

    // MARK: - MeteorEventPresenting

    func noticeScene() {
        cleanupDone = false
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        // Look toward the entry side (top-left, off-screen).
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        let direction = EventAttentionMath.direction(
            from: CGPoint(x: body.midX, y: body.midY),
            to: CGPoint(x: petFrame.minX - 120, y: activeVisibleFrame.maxY * 0.78)
        )
        if direction != .zero {
            attentionDirection = direction
            windowController?.setEventAttention(direction)
        }
    }

    func flightDidBegin(trajectory: MeteorTrajectory) {
        self.trajectory = trajectory
        ensurePanel()
        startTimer()
        // First frame immediately (still fully off-screen at t = 0).
        renderFrame(progress: 0, at: Date())
    }

    /// Called by the controller at phase boundaries; the 30 Hz render
    /// loop below does the per-frame work.
    func flightFrame(progress: CGFloat, at now: Date) {
        renderFrame(progress: progress, at: now)
    }

    func meteorDeparted() {
        // The meteor is fully beyond the display: release the gaze, then
        // the pet celebrates.
        attentionDirection = nil
        windowController?.setEventAttention(nil)
        windowController?.performCelebrationHop()
    }

    func cleanup() {
        guard !cleanupDone else { return }
        cleanupDone = true
        stopTimer()
        panel?.alphaValue = 0
        // Park the pooled panel fully off-screen below the visible area
        // so nothing can linger at the screen edge.
        if let panel {
            let visible = activeVisibleFrame
            panel.setFrameOrigin(CGPoint(
                x: visible.minX + 40,
                y: visible.minY - panel.frame.height - 80
            ))
        }
        trajectory = nil
        attentionDirection = nil
        windowController?.setEventAttention(nil)
        EventDiagnostics.meteor("CLEANED_UP")
    }

    // MARK: - 30 Hz render loop (independent of the 4 Hz scheduler)

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timerTick() {
        guard let controller else { return }
        guard let progress = controller.flightProgress(at: Date()) else {
            return
        }
        renderFrame(progress: progress, at: Date())
    }

    private func renderFrame(progress: CGFloat, at now: Date) {
        guard let trajectory, let panel else { return }
        let position = trajectory.position(at: progress)
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2
        ))
        viewState.rotationDegrees = trajectory.heading(at: progress) * 180 / .pi + 15
        panel.alphaValue = 1

        // Continuous attention tracking toward the moving meteor.
        if let petFrame = windowController?.currentFrame, petFrame != .zero {
            let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
            let direction = EventAttentionMath.direction(
                from: CGPoint(x: body.midX, y: body.midY),
                to: position
            )
            if direction != .zero {
                if attentionDirection == nil {
                    attentionDirection = direction
                    windowController?.setEventAttention(direction)
                } else if direction != attentionDirection {
                    attentionDirection = direction
                    windowController?.updateEventAttention(direction)
                }
            }
        }
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }
        let canvasScale = contentWidth / (881.0 / 1024)
        let canvasPt = 1024 * canvasScale
        let panelSize = CGSize(width: canvasPt + 28, height: canvasPt + 28)
        let newPanel = BirthdayPropPanel(size: panelSize, interactive: false)
        if let image = store.image(named: "meteor_celfilm.png") {
            viewState.image = image
            viewState.canvasSize = CGSize(width: canvasPt, height: canvasPt)
            viewState.rotationDegrees = 0
            let hosting = NSHostingView(rootView: MeteorView(state: viewState))
            hosting.frame = NSRect(origin: .zero, size: panelSize)
            newPanel.contentView = hosting
        }
        newPanel.alphaValue = 0
        panel = newPanel
    }
}

/// Live state for the meteor view (rotation updated per frame without
/// rebuilding the SwiftUI root).
final class MeteorViewState: ObservableObject {
    @Published var rotationDegrees: CGFloat = 0
    var image: NSImage?
    var canvasSize: CGSize = .zero
}

/// The meteor painting (unchanged artwork), banked along its heading.
struct MeteorView: View {
    @ObservedObject var state: MeteorViewState

    var body: some View {
        if let image = state.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: state.canvasSize.width, height: state.canvasSize.height)
                .rotationEffect(.degrees(Double(state.rotationDegrees)))
        }
    }
}
