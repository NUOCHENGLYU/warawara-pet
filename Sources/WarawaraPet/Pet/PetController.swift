import AppKit
import Combine

final class PetController: ObservableObject {
    @Published private(set) var state: PetState = .idle {
        didSet { stateDidChange(from: oldValue) }
    }
    @Published private(set) var hopProgress: CGFloat = 0
    @Published private(set) var settleProgress: CGFloat = 0
    @Published private(set) var floatProgress: CGFloat = 0
    @Published private(set) var dragDeformation: PetDeformation = .neutral
    @Published private(set) var curiosityPose: PetDeformation = .neutral

    let personalityTuning = PersonalityTuning.default

    private weak var windowController: PetWindowController?
    private let motionController: PetMotionController
    private let positionStore: PetPositionStore
    private var rng = SystemRandomSource()
    private var stateMachine = PetStateMachine()
    private var dragEstimator = DragDeformationEstimator()
    private var dragDecayTimer: Timer?
    private var autonomousTimer: Timer?
    private var awarenessTimer: Timer?
    private var awarenessTickCount = 0
    private var curiosityDetector: CuriosityDetector
    private var curiosityPoseEstimator: CuriosityPoseEstimator
    private var floatBaseFrame: CGRect?
    private var descentPending = false
    private var clickRevertItem: DispatchWorkItem?

    var idleTimeProvider: SystemIdleTimeProviding = CGEventSourceIdleTimeProvider()
    var mouseLocationProvider: () -> CGPoint = { NSEvent.mouseLocation }

    var isInTransientMotion: Bool {
        stateMachine.state == .hop || stateMachine.state == .float || stateMachine.state == .dragged
    }

    var isAutonomousScheduled: Bool { autonomousTimer != nil }

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
        curiosityDetector = CuriosityDetector(tuning: personalityTuning)
        curiosityPoseEstimator = CuriosityPoseEstimator(tuning: personalityTuning)
    }

    // MARK: - Startup

    func startAutonomousBehavior() {
        scheduleNextAutonomousAction()
        startAwarenessTimer()
    }

    // MARK: - State-driven scheduling (single place)
    // The autonomous timer exists only while idle; the awareness timer only
    // while idle/curious/sleepy. Both lifecycles are managed here.

    private func stateDidChange(from oldState: PetState) {
        guard state != oldState else { return }
        switch state {
        case .idle:
            scheduleNextAutonomousAction()
            startAwarenessTimer()
        case .curious, .sleepy:
            cancelAutonomousTimer()
            startAwarenessTimer()
        default:
            cancelAutonomousTimer()
            stopAwarenessTimer()
        }
    }

    // MARK: - Autonomous scheduler (one cancellable one-shot timer)

    private func scheduleNextAutonomousAction() {
        cancelAutonomousTimer()
        let decision = AutonomousScheduler.nextDecision(using: &rng, tuning: personalityTuning)
        autonomousTimer = Timer.scheduledTimer(
            withTimeInterval: decision.delay,
            repeats: false
        ) { [weak self] _ in
            self?.performAutonomousAction(decision.action)
        }
    }

    private func cancelAutonomousTimer() {
        autonomousTimer?.invalidate()
        autonomousTimer = nil
    }

    private func performAutonomousAction(_ action: AutonomousAction) {
        guard stateMachine.state == .idle else { return }
        switch action {
        case .hop:
            beginHop()
        case .float:
            beginFloat()
        }
    }

    // MARK: - Awareness timer (curiosity + sleepiness)

    private func startAwarenessTimer() {
        guard awarenessTimer == nil else { return }
        awarenessTickCount = 0
        awarenessTimer = Timer.scheduledTimer(
            withTimeInterval: personalityTuning.awarenessTickInterval,
            repeats: true
        ) { [weak self] _ in
            self?.awarenessTimerFired()
        }
    }

    private func stopAwarenessTimer() {
        awarenessTimer?.invalidate()
        awarenessTimer = nil
    }

    private func awarenessTimerFired() {
        awarenessTickCount += 1
        let checkSleepiness = awarenessTickCount % personalityTuning.sleepinessCheckInterval == 0
        awarenessTick(
            at: ProcessInfo.processInfo.systemUptime,
            evaluateSleepiness: checkSleepiness
        )
    }

    /// Deterministic tick entry point: evaluates curiosity (and, when
    /// asked, sleepiness) for the current state. Inert outside
    /// idle/curious/sleepy.
    func awarenessTick(at timestamp: TimeInterval, evaluateSleepiness: Bool = true) {
        switch stateMachine.state {
        case .idle:
            evaluateCuriosity(at: timestamp)
            if evaluateSleepiness { evaluateSleepiness() }
        case .curious:
            evaluateCuriosity(at: timestamp)
        case .sleepy:
            if evaluateSleepiness { evaluateSleepiness() }
        default:
            break
        }
    }

    private func evaluateCuriosity(at timestamp: TimeInterval) {
        guard let windowController else { return }
        let frame = windowController.currentFrame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let mouse = mouseLocationProvider()
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let distance = hypot(dx, dy)

        curiosityDetector.update(distance: distance, at: timestamp)

        switch stateMachine.state {
        case .idle:
            if curiosityDetector.isWatching {
                // Suppress autonomous hop/float while the pet is starting
                // to notice the cursor, so it does not wander away.
                cancelAutonomousTimer()
            } else if curiosityDetector.isEngaged {
                curiosityPoseEstimator.reset()
                guard stateMachine.transition(to: .curious) else { return }
                state = stateMachine.state
            } else if autonomousTimer == nil {
                scheduleNextAutonomousAction()
            }
        case .curious:
            if curiosityDetector.isEngaged {
                let direction = CGVector(
                    dx: dx / max(distance, 1),
                    dy: dy / max(distance, 1)
                )
                curiosityPoseEstimator.update(
                    direction: direction,
                    dwellProgress: 1,
                    at: timestamp
                )
                publishCuriosityPoseIfChanged()
            } else {
                guard stateMachine.transition(to: .idle) else { return }
                state = stateMachine.state
                curiosityPose = .neutral
            }
        default:
            break
        }
    }

    private func publishCuriosityPoseIfChanged() {
        let pose = curiosityPoseEstimator.pose
        if pose != curiosityPose {
            curiosityPose = pose
        }
    }

    private func evaluateSleepiness() {
        let idleSeconds = idleTimeProvider.secondsSinceLastUserActivity()
        switch SleepinessEvaluator.decision(
            state: stateMachine.state,
            idleSeconds: idleSeconds,
            tuning: personalityTuning
        ) {
        case .enterSleepy:
            guard stateMachine.transition(to: .sleepy) else { return }
            state = stateMachine.state
        case .enterSleeping:
            guard stateMachine.transition(to: .sleeping) else { return }
            state = stateMachine.state
        case .returnToIdle:
            guard stateMachine.transition(to: .idle) else { return }
            state = stateMachine.state
        case nil:
            break
        }
    }

    // MARK: - Hop

    private func beginHop() {
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
    }

    // MARK: - Float
    // The float base frame is the stable, clamped frame captured when the
    // float begins. Normal completion returns to it; click interruption
    // descends to it; drag interruption discards it.

    func beginFloat() {
        guard stateMachine.transition(to: .float) else { return }
        state = stateMachine.state
        let parameters = FloatParameters.random(using: &rng, tuning: personalityTuning)
        floatBaseFrame = windowController?.currentFrame
        guard let startFrame = floatBaseFrame, let windowController else { return }
        motionController.startFloat(
            from: startFrame,
            parameters: parameters,
            progress: { [weak self] progress in self?.floatProgress = progress },
            completion: { [weak self] _ in self?.finishFloat() }
        )
    }

    private func finishFloat() {
        floatProgress = 0
        guard stateMachine.transition(to: .settling) else { return }
        state = stateMachine.state
        let base = floatBaseFrame ?? windowController?.currentFrame ?? .zero
        floatBaseFrame = nil
        startSettleMotion(from: base, to: base)
    }

    // MARK: - Click

    func handleClick() {
        guard stateMachine.state != .hop else { return }
        if stateMachine.state == .float {
            // Click interrupts the float: squash in place (no snap back to
            // the base), then descend gently after the reaction.
            motionController.cancelMotion()
            floatProgress = 0
            descentPending = true
        } else if stateMachine.state == .clicked {
            stateMachine.transition(to: .clicked)
        } else {
            guard stateMachine.transition(to: .clicked) else { return }
        }
        state = stateMachine.state
        scheduleClickRevert()
    }

    private func scheduleClickRevert() {
        clickRevertItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.completeClickReaction()
        }
        clickRevertItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickSquashDuration, execute: item)
    }

    /// Deterministic entry point for the click-reaction completion.
    func completeClickReaction() {
        guard stateMachine.state == .clicked else { return }
        if descentPending {
            descentPending = false
            let base = floatBaseFrame
            floatBaseFrame = nil
            if let base, let windowController, stateMachine.transition(to: .settling) {
                state = stateMachine.state
                startSettleMotion(from: windowController.currentFrame, to: base)
            } else {
                guard stateMachine.transition(to: .idle) else { return }
                state = stateMachine.state
            }
        } else {
            guard stateMachine.transition(to: .idle) else { return }
            state = stateMachine.state
        }
    }

    // MARK: - Drag

    func handleDragBegan(grabVector: CGVector) {
        clickRevertItem?.cancel()
        motionController.cancelMotion()
        hopProgress = 0
        settleProgress = 0
        floatProgress = 0
        floatBaseFrame = nil
        descentPending = false
        curiosityPose = .neutral
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
        startSettleMotion(from: windowController.currentFrame, to: windowController.currentFrame)
    }

    private func startSettleMotion(from startFrame: CGRect, to targetFrame: CGRect) {
        motionController.startSettle(
            from: startFrame,
            to: targetFrame,
            progress: { [weak self] progress in self?.settleProgress = progress },
            completion: { [weak self] finalFrame in self?.finishSettle(finalFrame: finalFrame) }
        )
    }

    private func finishSettle(finalFrame: CGRect) {
        guard stateMachine.transition(to: .idle) else { return }
        state = stateMachine.state
        settleProgress = 0
        positionStore.saveOrigin(finalFrame.origin)
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
