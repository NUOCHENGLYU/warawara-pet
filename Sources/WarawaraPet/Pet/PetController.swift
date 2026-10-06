import AppKit
import Combine

final class PetController: ObservableObject {
    @Published private(set) var state: PetState = .idle
    @Published private(set) var hopProgress: CGFloat = 0
    @Published private(set) var settleProgress: CGFloat = 0
    @Published private(set) var dragDeformation: PetDeformation = .neutral

    private weak var windowController: PetWindowController?
    private let motionController: PetMotionController
    private let positionStore: PetPositionStore
    private var rng = SystemRandomSource()
    private var stateMachine = PetStateMachine()
    private var dragEstimator = DragDeformationEstimator()
    private var dragDecayTimer: Timer?
    private var hopTimer: Timer?
    private var clickRevertItem: DispatchWorkItem?

    private static let hopDelayRange: ClosedRange<TimeInterval> = 6...14
    private static let clickSquashDuration: TimeInterval = 0.28
    private static let dragTickInterval: TimeInterval = 1.0 / 30.0

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

    func handleDragBegan(grabVector: CGVector) {
        cancelHopTimer()
        clickRevertItem?.cancel()
        motionController.cancelMotion()
        hopProgress = 0
        settleProgress = 0
        guard stateMachine.transition(to: .dragged) else { return }
        state = stateMachine.state
        dragEstimator.beginDrag(grabVector: grabVector)
        startDragDecayTimer()
    }

    func handleDragMoved(deltaX: CGFloat, deltaY: CGFloat, at timestamp: TimeInterval) {
        guard stateMachine.state == .dragged else { return }
        dragEstimator.update(deltaX: deltaX, deltaY: deltaY, at: timestamp)
        publishDragDeformationIfChanged()
    }

    func handleDragEnded() {
        guard stateMachine.state == .dragged,
              stateMachine.transition(to: .settling) else { return }
        state = stateMachine.state
        dragDeformation = .neutral
        dragDecayTimer?.invalidate()
        dragDecayTimer = nil
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

    // MARK: - Drag decay
    // While the pet is held (state == dragged) but the mouse is stationary,
    // a lightweight tick relaxes the smoothed velocity toward zero so the
    // deformation eases back to neutral around the fixed grab anchor. The
    // timer exists only during dragging and is cancelled on drag end.

    private func startDragDecayTimer() {
        dragDecayTimer?.invalidate()
        dragDecayTimer = Timer.scheduledTimer(
            withTimeInterval: Self.dragTickInterval,
            repeats: true
        ) { [weak self] _ in
            self?.tickDragDecay()
        }
    }

    private func tickDragDecay() {
        // ProcessInfo.systemUptime matches NSEvent.timestamp's clock.
        dragTick(at: ProcessInfo.processInfo.systemUptime)
    }

    /// Deterministic tick entry point: applies held-still decay once while
    /// the pet is still being dragged. Inert in any other state.
    func dragTick(at timestamp: TimeInterval) {
        guard stateMachine.state == .dragged else { return }
        dragEstimator.decay(at: timestamp)
        publishDragDeformationIfChanged()
    }

    private func publishDragDeformationIfChanged() {
        let deformation = dragEstimator.deformation
        if deformation != dragDeformation {
            dragDeformation = deformation
        }
    }
}
