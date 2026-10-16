import Foundation

/// Phases of the birthday event. The coordinator owns all timing and
/// transitions; the production presenter only realizes UI cues.
enum BirthdayPhase: Equatable {
    case idle
    /// Main pet visibly notices the arriving companions (event attention
    /// drives the accepted curious/turn pipeline).
    case noticing
    /// Companions enter carrying the gifts (cake + envelope attached to
    /// carriers through the Phase 3 group sequence).
    case gathering
    /// Gifts are delivered to the stable front-of-pet layout; staggered
    /// celebration hops.
    case celebrating
    /// Companions ascend and leave; the envelope is activated as the
    /// readable gift.
    case awaitingLetter
    /// Persistence written; coordinator returns to idle.
    case completed
    /// Interrupted before completion: cleaned up, NOT completed.
    case cancelled
}

/// Centralized birthday timing. Adjust here — never scattered.
struct BirthdayTiming {
    /// Attention beat before the companions enter.
    var noticingDuration: TimeInterval = 2.4
    /// A small hop while noticing (offset from event start).
    var attentionHopDelay: TimeInterval = 1.4
    /// Companions start entering at this offset from event start.
    var gatherStartDelay: TimeInterval = 2.8
    /// Gifts detach from the carriers and ease to the front layout at
    /// this offset after the gather starts.
    var deliveryDelayAfterGatherStart: TimeInterval = 5.0
    /// Celebration hops relative to the gather start.
    var celebrationHopOffsets: [TimeInterval] = [6.2, 8.8]

    static let `default` = BirthdayTiming()
}

/// UI realization contract. The production app provides a real
/// presenter; tests provide a recording spy.
protocol BirthdayEventPresenting: AnyObject {
    /// The main pet turns to look toward the arriving companions.
    func noticeCompanionsArriving()
    /// Cake and envelope fade in attached to carrier companions.
    func presentCarriedProps()
    /// Props ease to the stable front-of-pet layout (desktop plane).
    func deliverPropsToPet()
    /// The envelope becomes clickable and the letter is available.
    func activateEnvelope()
    /// Cake fades out gently after the celebration.
    func hideCake()
    func startCompanionGroup()
    func cancelCompanionGroup()
    func performMainPetHop()
    /// Releases the event attention (pet returns to normal life).
    func clearAttention()
    /// Called once the envelope is fully available (persistence safe point).
    func envelopeDidBecomeAvailable()
}

/// Owns the birthday event lifecycle: eligibility, triggering, phase
/// ordering, timing, cancellation, restart recovery, and persistence.
/// It never replaces the main pet state machine — it orchestrates
/// established behaviors around it.
final class BirthdayEventCoordinator {
    enum Trigger: Equatable {
        /// Calendar-based automatic trigger (consumes the annual record).
        case automatic
        /// Manual replay on any date (never consumes the annual record).
        case replay
    }

    private(set) var phase: BirthdayPhase = .idle
    private(set) var trigger: Trigger?
    let clock: BirthdayClock
    let persistence: BirthdayPersistence
    let timing: BirthdayTiming
    weak var presenter: BirthdayEventPresenting?

    /// Set by the production app when the main pet is being dragged, so
    /// triggering is deferred until the pet is free.
    var isPetBusy: (() -> Bool)?

    private var startedAt: Date?
    private var gatherStartedAt: Date?
    private var firedHops: Set<Int> = []
    private var pendingTrigger: Trigger?
    private var ranThisLaunch = false
    private(set) var groupActive = false
    private(set) var propsDelivered = false

    var isRunning: Bool { phase != .idle }

    init(
        clock: BirthdayClock = SystemBirthdayClock(),
        persistence: BirthdayPersistence = BirthdayPersistence(),
        timing: BirthdayTiming = .default
    ) {
        self.clock = clock
        self.persistence = persistence
        self.timing = timing
    }

    // MARK: - Eligibility

    var isBirthdayToday: Bool {
        BirthdayDateMath.isBirthday(date: clock.now(), calendar: clock.calendar)
    }

    var currentYear: Int {
        clock.calendar.component(.year, from: clock.now())
    }

    var isCompletedThisYear: Bool {
        persistence.isCompleted(year: currentYear)
    }

    var shouldTriggerAutomatically: Bool {
        isBirthdayToday && !isCompletedThisYear && !ranThisLaunch
    }

    var shouldShowEnvelope: Bool {
        persistence.envelopeUnlocked || isBirthdayToday
    }

    // MARK: - Triggering

    func requestTrigger(_ trigger: Trigger) {
        guard phase == .idle else { return }
        pendingTrigger = trigger
    }

    func requestCancellation() {
        guard isRunning else { return }
        cancelEvent()
    }

    func servicePendingTrigger() {
        guard let pending = pendingTrigger else { return }
        if isPetBusy?() == true { return }
        pendingTrigger = nil
        begin(pending)
    }

    func checkAutomaticTrigger() {
        guard phase == .idle, pendingTrigger == nil else { return }
        if shouldTriggerAutomatically {
            requestTrigger(.automatic)
        }
    }

    private func begin(_ trigger: Trigger) {
        guard phase == .idle else { return }
        ranThisLaunch = true
        self.trigger = trigger
        startedAt = clock.now()
        gatherStartedAt = nil
        firedHops.removeAll()
        groupActive = false
        propsDelivered = false
        phase = .noticing
        presenter?.noticeCompanionsArriving()
        presenter?.performMainPetHop()
    }

    // MARK: - Advancing

    func advance() {
        advance(at: clock.now())
    }

    func advance(at now: Date) {
        switch phase {
        case .idle:
            return
        case .noticing:
            advanceNoticing(now)
        case .gathering:
            advanceGathering(now)
        case .celebrating:
            advanceCelebrating(now)
        case .awaitingLetter, .completed, .cancelled:
            return
        }
    }

    private func advanceNoticing(_ now: Date) {
        guard let startedAt else { return }
        let elapsed = now.timeIntervalSince(startedAt)
        if !firedHops.contains(1), elapsed >= timing.attentionHopDelay {
            firedHops.insert(1)
            presenter?.performMainPetHop()
        }
        if elapsed >= timing.gatherStartDelay {
            phase = .gathering
            presenter?.presentCarriedProps()
            presenter?.startCompanionGroup()
        }
    }

    private func advanceGathering(_ now: Date) {
        guard let gatherStartedAt else { return }
        let elapsed = now.timeIntervalSince(gatherStartedAt)
        if !propsDelivered, elapsed >= timing.deliveryDelayAfterGatherStart {
            propsDelivered = true
            phase = .celebrating
            presenter?.deliverPropsToPet()
        }
    }

    private func advanceCelebrating(_ now: Date) {
        guard let gatherStartedAt else { return }
        let elapsed = now.timeIntervalSince(gatherStartedAt)
        for (index, offset) in timing.celebrationHopOffsets.enumerated()
        where !firedHops.contains(100 + index) && elapsed >= offset {
            firedHops.insert(100 + index)
            presenter?.performMainPetHop()
        }
    }

    // MARK: - Group lifecycle notifications

    func companionGroupDidStart() {
        groupActive = true
        gatherStartedAt = gatherStartedAt ?? clock.now()
    }

    func companionGroupDidEnd() {
        guard groupActive else { return }
        groupActive = false
        guard phase == .gathering || phase == .celebrating else { return }
        phase = .awaitingLetter
        presenter?.hideCake()
        presenter?.activateEnvelope()
        presenter?.clearAttention()
        persistence.markEnvelopeUnlocked()
        if trigger == .automatic {
            persistence.markCompleted(year: currentYear)
        }
        presenter?.envelopeDidBecomeAvailable()
        phase = .completed
        resetToIdle()
    }

    // MARK: - Completion / cancellation

    private func cancelEvent() {
        if groupActive {
            presenter?.cancelCompanionGroup()
            groupActive = false
        }
        presenter?.clearAttention()
        if propsDelivered {
            // The gift has already been delivered: keep it as the
            // readable gift even though the event was interrupted.
            presenter?.activateEnvelope()
            presenter?.hideCake()
            persistence.markEnvelopeUnlocked()
        } else {
            presenter?.hideCake()
        }
        phase = .cancelled
        resetToIdle()
    }

    private func resetToIdle() {
        startedAt = nil
        gatherStartedAt = nil
        firedHops.removeAll()
        propsDelivered = false
        trigger = nil
        phase = .idle
    }
}
