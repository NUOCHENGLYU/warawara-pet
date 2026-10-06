import AppKit
import Combine

final class PetController: ObservableObject {
    @Published private(set) var state: PetState = .idle
    @Published private(set) var hopProgress: CGFloat = 0
    @Published private(set) var settleProgress: CGFloat = 0
    @Published private(set) var dragTilt: CGFloat = 0

    private weak var windowController: PetWindowController?
    private let motionController: PetMotionController
    private let positionStore: PetPositionStore
    private var rng = SystemRandomSource()
    private var stateMachine = PetStateMachine()
    private var hopTimer: Timer?
    private var clickRevertItem: DispatchWorkItem?

    private static let hopDelayRange: ClosedRange<TimeInterval> = 6...14
    private static let clickSquashDuration: TimeInterval = 0.28

    init(
        windowController: PetWindowController,
        motionController: PetMotionController,
        positionStore: PetPositionStore
    ) {
        self.windowController = windowController
        self.motionController = motionController
        self.positionStore = positionStore
    }

    // MARK: - Idle scheduling
    // Main-thread only. The pending hop is always cancelled when leaving idle.

    func startIdleSchedule() {
        cancelHopTimer()
        let delay = RandomBounds.randomDelay(in: Self.hopDelayRange, using: &rng)
        hopTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.beginHop()
        }
    }

    private func cancelHopTimer() {
        hopTimer?.invalidate()
        hopTimer = nil
    }

    private func beginHop() {
        cancelHopTimer()
        guard stateMachine.transition(to: .hop) else { return }
        state = stateMachine.state
        let parameters = HopParameters.random(using: &rng)
        guard let windowController else { return }
        motionController.startHop(
            from: windowController.currentFrame,
            parameters: parameters,
            progress: { [weak self] progress in self?.hopProgress = progress },
            completion: { [weak self] finalFrame in self?.finishHop(landingAt: finalFrame) }
        )
    }

    private func finishHop(landingAt frame: CGRect) {
        guard stateMachine.transition(to: .idle) else { return }
        state = stateMachine.state
        hopProgress = 0
        positionStore.saveOrigin(frame.origin)
        startIdleSchedule()
    }

    // MARK: - Click

    func handleClick() {
        guard stateMachine.state != .hop else { return }
        if stateMachine.state == .clicked {
            stateMachine.transition(to: .clicked)
        } else {
            guard stateMachine.transition(to: .clicked) else { return }
        }
        state = stateMachine.state
        cancelHopTimer()
        scheduleClickRevert()
    }

    private func scheduleClickRevert() {
        clickRevertItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.revertClick()
        }
        clickRevertItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickSquashDuration, execute: item)
    }

    private func revertClick() {
        guard stateMachine.state == .clicked,
              stateMachine.transition(to: .idle) else { return }
        state = stateMachine.state
        startIdleSchedule()
    }

    // MARK: - Drag

    func handleDragBegan() {
        cancelHopTimer()
        clickRevertItem?.cancel()
        motionController.cancelMotion()
        hopProgress = 0
        settleProgress = 0
        guard stateMachine.transition(to: .dragged) else { return }
        state = stateMachine.state
    }

    func handleDragMoved(tilt: CGFloat) {
        guard stateMachine.state == .dragged else { return }
        dragTilt = tilt
    }

    func handleDragEnded() {
        guard stateMachine.state == .dragged,
              stateMachine.transition(to: .settling) else { return }
        state = stateMachine.state
        dragTilt = 0
        guard let windowController else { return }
        motionController.startSettle(
            from: windowController.currentFrame,
            progress: { [weak self] progress in self?.settleProgress = progress },
            completion: { [weak self] finalFrame in self?.finishSettle(finalFrame: finalFrame) }
        )
    }

    private func finishSettle(finalFrame: CGRect) {
        guard stateMachine.transition(to: .idle) else { return }
        state = stateMachine.state
        settleProgress = 0
        positionStore.saveOrigin(finalFrame.origin)
        startIdleSchedule()
    }
}
