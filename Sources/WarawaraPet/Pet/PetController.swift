import AppKit
import Combine

final class PetController: ObservableObject {
    @Published private(set) var state: PetState = .idle {
        didSet { stateDidChange(from: oldValue) }
    }
    @Published private(set) var hopProgress: CGFloat = 0
    @Published private(set) var settleProgress: CGFloat = 0
    @Published private(set) var floatProgress: CGFloat = 0
    @Published private(set) var floatDeformation: PetDeformation = .neutral
    @Published private(set) var dragDeformation: PetDeformation = .neutral
    @Published private(set) var curiosityPose: PetDeformation = .neutral
    /// Smoothed cursor direction while curious; feeds the layered
    /// expression system's continuous gaze. Zero otherwise.
    @Published private(set) var curiosityDirection: CGVector = .zero
    /// Event-driven attention (birthday): when non-nil it OVERRIDES the
    /// mouse-driven gaze and drives the curious state so the pet visibly
    /// looks at something specific (arriving companions / gifts).
    @Published private(set) var eventAttentionDirection: CGVector?
    private var eventAttentionActive = false

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
    private var curiosityTrackerTimer: Timer?
    private var curiosityDetector: CuriosityDetector
    private var curiosityPoseEstimator: CuriosityPoseEstimator
    private var floatBaseFrame: CGRect?
    private var descentPending = false
    private var nextFloatEligibleAt: TimeInterval = 0
    private var clickRevertItem: DispatchWorkItem?

    var idleTimeProvider: SystemIdleTimeProviding = CGEventSourceIdleTimeProvider()
    var mouseLocationProvider: () -> CGPoint = { NSEvent.mouseLocation }

    /// Notified whenever the user interacts with the main pet (click or
    /// drag). The group sequence uses this to cancel itself immediately:
    /// user interaction always wins.
    var onUserInteraction: (() -> Void)?

    private var groupSequenceActive = false

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
            if groupSequenceActive {
                // A group sequence is running: keep autonomous hop/float
                // paused until it ends.
                cancelAutonomousTimer()
            } else {
                scheduleNextAutonomousAction()
            }
            startAwarenessTimer()
            stopCuriosityTracker()
        case .curious:
            cancelAutonomousTimer()
            startAwarenessTimer()
            startCuriosityTracker()
        case .sleepy:
            cancelAutonomousTimer()
            startAwarenessTimer()
            stopCuriosityTracker()
        default:
            cancelAutonomousTimer()
            stopAwarenessTimer()
            stopCuriosityTracker()
        }
    }

    /// Called by the group sequence when it starts (true) and fully ends
    /// (false) so autonomous hop/float scheduling pauses during the
    /// sequence and resumes afterwards.
    func setGroupSequenceActive(_ active: Bool) {
        guard active != groupSequenceActive else { return }
        groupSequenceActive = active
        if active {
            cancelAutonomousTimer()
        } else if stateMachine.state == .idle {
            scheduleNextAutonomousAction()
        }
    }

    // MARK: - Autonomous scheduler (one cancellable one-shot timer)

    private func scheduleNextAutonomousAction() {
        cancelAutonomousTimer()
        let delay = AutonomousScheduler.nextDelay(using: &rng, tuning: personalityTuning)
        autonomousTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            self?.performAutonomousAction()
        }
    }

    private func cancelAutonomousTimer() {
        autonomousTimer?.invalidate()
        autonomousTimer = nil
    }

    private func performAutonomousAction() {
        guard stateMachine.state == .idle else { return }
        let action = AutonomousScheduler.nextAction(
            now: ProcessInfo.processInfo.systemUptime,
            floatEligibleSince: nextFloatEligibleAt,
            using: &rng,
            tuning: personalityTuning
        )
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
            if evaluateSleepiness { evaluateSleepinessNow() }
        case .curious:
            evaluateCuriosity(at: timestamp)
        case .sleepy:
            if evaluateSleepiness { evaluateSleepinessNow() }
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
            } else if autonomousTimer == nil && !groupSequenceActive {
                // Do not reschedule while a group sequence is running:
                // autonomous actions stay paused for its duration.
                scheduleNextAutonomousAction()
            }
        case .curious:
            // Event-driven attention OWNS the curious state: the
            // autonomous curiosity logic must never pull the pet back to
            // idle while an event is being attended (this was the
            // one-frame attention flicker: the 150 ms awareness tick
            // exited curious before the event could hold it).
            if eventAttentionActive { return }
            // The 30 Hz tracker owns the visual pose; the awareness tick
            // only decides when to stop being curious.
            if !curiosityDetector.isEngaged {
                guard stateMachine.transition(to: .idle) else { return }
                state = stateMachine.state
                curiosityPose = .neutral
                curiosityDirection = .zero
            }
        default:
            break
        }
    }

    /// Event-driven attention performance: the pet turns to look toward
    /// `direction` (reusing the accepted curious state and 2.5D turn).
    /// Pass nil to release the attention and return to idle.
    /// Acquisition is explicit; while active the event OWNS the gaze and
    /// state until released (autonomous curiosity can never exit it).
    func setEventAttention(_ direction: CGVector?) {
        guard let direction else {
            releaseEventAttention()
            return
        }
        guard stateMachine.state == .idle || stateMachine.state == .curious else { return }
        if stateMachine.state == .idle {
            guard stateMachine.transition(to: .curious) else { return }
            state = stateMachine.state
        }
        eventAttentionActive = true
        eventAttentionDirection = direction
        curiosityDirection = direction
        EventDiagnostics.attentionAcquired(direction: direction)
    }

    /// Per-frame tracking update while event attention holds (moving
    /// props: falling envelope, flying airplane...). Never transitions
    /// state; the direction change is smoothed by the expression system.
    func updateEventAttention(_ direction: CGVector) {
        guard eventAttentionActive else { return }
        eventAttentionDirection = direction
        if curiosityDirection != direction {
            curiosityDirection = direction
        }
    }

    private func releaseEventAttention() {
        guard eventAttentionActive else { return }
        eventAttentionActive = false
        eventAttentionDirection = nil
        curiosityDirection = .zero
        curiosityPose = .neutral
        EventDiagnostics.attentionReleased()
        if stateMachine.state == .curious {
            _ = stateMachine.transition(to: .idle)
            state = stateMachine.state
        }
    }

    /// True while the mouse tracker must yield to event attention.
    var isEventAttentionActive: Bool { eventAttentionActive }

    // MARK: - Curiosity visual tracking (active only while curious)
    // State detection stays on the low-frequency awareness timer; this
    // separate loop samples the cursor at ~30 Hz only while engaged so the
    // following pose is fluid without permanent idle polling.

    private func startCuriosityTracker() {
        guard curiosityTrackerTimer == nil else { return }
        curiosityTrackerTimer = Timer.scheduledTimer(
            withTimeInterval: personalityTuning.curiosityTrackingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.curiosityTrackerTick()
        }
    }

    private func stopCuriosityTracker() {
        curiosityTrackerTimer?.invalidate()
        curiosityTrackerTimer = nil
    }

    private func curiosityTrackerTick() {
        curiosityTrackingTick(at: ProcessInfo.processInfo.systemUptime)
    }

    /// Deterministic entry point for the visual tracker; inert outside the
    /// curious state.
    func curiosityTrackingTick(at timestamp: TimeInterval) {
        guard stateMachine.state == .curious else { return }
        updateCuriosityPose(at: timestamp)
    }

    private func updateCuriosityPose(at timestamp: TimeInterval) {
        guard let windowController else { return }
        let frame = windowController.currentFrame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let mouse = mouseLocationProvider()
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let distance = hypot(dx, dy)
        let direction = CGVector(
            dx: dx / max(distance, 1),
            dy: dy / max(distance, 1)
        )
        curiosityPoseEstimator.update(
            direction: direction,
            dwellProgress: 1,
            at: timestamp
        )
        // Event attention (birthday) owns the gaze and pose while active:
        // the mouse tracker keeps sampling but never publishes.
        guard !eventAttentionActive else { return }
        // Small deadband on the gaze publish only (the pose pipeline keeps
        // the raw smoothed direction): a still cursor produces exactly
        // zero gaze drift instead of micro-jitter.
        let gaze = CuriosityPoseMath.deadbanded(
            curiosityPoseEstimator.direction,
            threshold: 0.02
        )
        if gaze != curiosityDirection {
            curiosityDirection = gaze
        }
        publishCuriosityPoseIfChanged()
    }

    private func publishCuriosityPoseIfChanged() {
        let pose = curiosityPoseEstimator.pose
        if pose != curiosityPose {
            curiosityPose = pose
        }
    }

    private func evaluateSleepinessNow() {
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

    /// Public birthday hook: a small celebratory hop of the main pet.
    /// Inert unless the pet is idle (the event never fights the state
    /// machine).
    func performBirthdayHop() {
        guard stateMachine.state == .idle else { return }
        beginHop()
    }

    /// Seasonal/daily celebration: a SMALL deterministic hop (the
    /// birthday keeps its full random hop). Inert outside idle — event
    /// choreography releases attention before calling this.
    func performCelebrationHop() {
        guard stateMachine.state == .idle else { return }
        beginHop(parameters: HopParameters(height: 46, drift: 0, duration: 0.75))
    }

    private func beginHop(parameters: HopParameters? = nil) {
        guard stateMachine.transition(to: .hop) else { return }
        state = stateMachine.state
        startHopMotion(parameters: parameters)
    }

    private func startHopMotion(parameters: HopParameters? = nil) {
        let hopParameters = parameters ?? HopParameters.random(using: &rng)
        guard let windowController else { return }
        motionController.startHop(
            from: windowController.currentFrame,
            parameters: hopParameters,
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
        startFloatMotion()
    }

    private func startFloatMotion() {
        let parameters = FloatParameters.random(using: &rng, tuning: personalityTuning)
        floatBaseFrame = windowController?.currentFrame
        let cooldown = RandomBounds.randomDelay(
            in: personalityTuning.floatCooldownMin...personalityTuning.floatCooldownMax,
            using: &rng
        )
        nextFloatEligibleAt = ProcessInfo.processInfo.systemUptime + cooldown
        guard let startFrame = floatBaseFrame, let windowController else { return }
        motionController.startFloat(
            from: startFrame,
            parameters: parameters,
            progress: { [weak self] progress in
                guard let self else { return }
                self.floatProgress = progress
                self.floatDeformation = FloatPoseMath.pose(
                    at: progress,
                    parameters: parameters,
                    tuning: self.personalityTuning
                )
            },
            completion: { [weak self] _ in self?.finishFloat() }
        )
    }

    private func finishFloat() {
        floatProgress = 0
        floatDeformation = .neutral
        guard stateMachine.transition(to: .idle) else { return }
        state = stateMachine.state
        floatBaseFrame = nil
        if let frame = windowController?.currentFrame {
            positionStore.saveOrigin(frame.origin)
        }
    }

    // MARK: - Click

    func handleClick() {
        onUserInteraction?()
        guard stateMachine.state != .hop else { return }
        if stateMachine.state == .float {
            // Click interrupts the float: squash in place (no snap back to
            // the base), then descend gently after the reaction.
            motionController.cancelMotion()
            floatProgress = 0
            floatDeformation = .neutral
            descentPending = true
            guard stateMachine.transition(to: .clicked) else { return }
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
        onUserInteraction?()
        clickRevertItem?.cancel()
        motionController.cancelMotion()
        hopProgress = 0
        settleProgress = 0
        floatProgress = 0
        floatDeformation = .neutral
        floatBaseFrame = nil
        descentPending = false
        curiosityPose = .neutral
        curiosityDirection = .zero
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
