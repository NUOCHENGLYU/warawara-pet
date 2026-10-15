import Foundation

/// Phases of the birthday event. The coordinator owns all timing and
/// transitions; the production presenter only realizes UI cues.
enum BirthdayPhase: Equatable {
    case idle
    /// Main pet's gentle surprise reaction (hops + normal curiosity).
    case surprise
    /// Cake fades in near the pet.
    case cakeArriving
    /// Companions gather; celebration hops fire with stagger.
    case gathering
    /// Companions ascend (driven by the Phase 3 group sequence itself).
    case ascending
    /// Envelope appears and fades in.
    case envelopeReveal
    /// Envelope is clickable; the pet lives its normal life.
    case awaitingLetter
    /// Persistence written; coordinator returns to idle.
    case completed
    /// Interrupted before completion: cleaned up, NOT completed.
    case cancelled
}

/// Centralized birthday timing. Adjust here — never scattered.
struct BirthdayTiming {
    /// First hop at t=0, second at this offset.
    var secondHopDelay: TimeInterval = 2.4
    /// Cake starts fading in at this offset.
    var cakeDelay: TimeInterval = 3.4
    var cakeFadeDuration: TimeInterval = 1.4
    /// Companions start gathering at this offset.
    var gatherDelay: TimeInterval = 5.0
    /// Celebration hops relative to the gather start.
    var celebrationHopOffsets: [TimeInterval] = [5.0, 8.0]
    /// Warm pause between ascent and envelope appearance.
    var postAscentPause: TimeInterval = 1.2
    var envelopeFadeDuration: TimeInterval = 1.6

    static let `default` = BirthdayTiming()
}

/// UI realization contract. The production app provides a real
/// presenter; tests provide a recording spy.
protocol BirthdayEventPresenting: AnyObject {
    func presentCake()
    func hideCake()
    func presentSparkles()
    func hideSparkles()
    func presentEnvelope()
    func hideEnvelope()
    func startCompanionGroup()
    func cancelCompanionGroup()
    func performMainPetHop()
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
    private var envelopeStartedAt: Date?
    private var firedHops: Set<Int> = []
    private var pendingTrigger: Trigger?
    private var ranThisLaunch = false
    private(set) var groupActive = false

    var isRunning: Bool { phase != .idle }
    var isEnvelopePhase: Bool {
        phase == .envelopeReveal || phase == .awaitingLetter || phase == .completed
    }

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

    /// Automatic eligibility: local October 17 AND not yet completed
    /// this local year AND not already run in this launch.
    var shouldTriggerAutomatically: Bool {
        isBirthdayToday && !isCompletedThisYear && !ranThisLaunch
    }

    /// True while the persistent envelope should be visible (unlocked
    /// once, or it is the birthday today).
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

    /// Called periodically (and from tests): consumes a pending trigger
    /// once the pet is not busy. Deferred while dragging.
    func servicePendingTrigger() {
        guard let pending = pendingTrigger else { return }
        if isPetBusy?() == true { return }
        pendingTrigger = nil
        begin(pending)
    }

    /// Midnight transition support: the app calls this periodically;
    /// triggers automatically the first time the local calendar crosses
    /// into October 17 while the app keeps running.
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
        envelopeStartedAt = nil
        firedHops.removeAll()
        groupActive = false
        phase = .surprise
        presenter?.performMainPetHop()
    }

    // MARK: - Advancing

    /// Advances the event using the injected clock. The production app
    /// calls this from a light timer; tests call it directly.
    func advance() {
        advance(at: clock.now())
    }

    func advance(at now: Date) {
        switch phase {
        case .idle:
            return
        case .surprise:
            advanceSurprise(now)
        case .cakeArriving:
            if now.timeIntervalSince(startedAt ?? now) >= timing.cakeDelay + timing.cakeFadeDuration {
                phase = .gathering
                gatherStartedAt = now
                presenter?.presentSparkles()
                presenter?.startCompanionGroup()
            }
        case .gathering:
            advanceGathering(now)
        case .ascending:
            // Ascension is driven by the Phase 3 group sequence; the
            // presenter notifies groupDidEnd when it finishes.
            return
        case .envelopeReveal:
            if now.timeIntervalSince(envelopeStartedAt ?? now) >= timing.envelopeFadeDuration {
                completeEvent()
            }
        case .awaitingLetter, .completed, .cancelled:
            return
        }
    }

    private func advanceSurprise(_ now: Date) {
        guard let startedAt else { return }
        let elapsed = now.timeIntervalSince(startedAt)
        if !firedHops.contains(1), elapsed >= timing.secondHopDelay {
            firedHops.insert(1)
            presenter?.performMainPetHop()
        }
        if elapsed >= timing.cakeDelay {
            phase = .cakeArriving
            presenter?.presentCake()
        }
    }

    private func advanceGathering(_ now: Date) {
        guard let gatherStartedAt else { return }
        let elapsed = now.timeIntervalSince(gatherStartedAt)
        for (index, offset) in timing.celebrationHopOffsets.enumerated()
        where !firedHops.contains(100 + index) && elapsed >= offset {
            firedHops.insert(100 + index)
            presenter?.performMainPetHop()
        }
        // The group sequence signals its own end via companionGroupDidEnd.
    }

    // MARK: - Group lifecycle notifications (from the production presenter)

    func companionGroupDidStart() {
        groupActive = true
        if phase == .gathering {
            phase = .ascending
        }
    }

    func companionGroupDidEnd() {
        guard groupActive else { return }
        groupActive = false
        guard phase == .ascending || phase == .gathering else { return }
        presenter?.hideSparkles()
        presenter?.hideCake()
        phase = .envelopeReveal
        envelopeStartedAt = clock.now()
        presenter?.presentEnvelope()
    }

    // MARK: - Completion / cancellation

    private func completeEvent() {
        guard phase == .envelopeReveal else { return }
        phase = .awaitingLetter
        persistence.markEnvelopeUnlocked()
        if trigger == .automatic {
            persistence.markCompleted(year: currentYear)
        }
        presenter?.envelopeDidBecomeAvailable()
        phase = .completed
        resetToIdle()
    }

    private func cancelEvent() {
        if groupActive {
            presenter?.cancelCompanionGroup()
            groupActive = false
        }
        presenter?.hideCake()
        presenter?.hideSparkles()
        if isEnvelopePhase {
            presenter?.hideEnvelope()
        }
        phase = .cancelled
        resetToIdle()
    }

    private func resetToIdle() {
        startedAt = nil
        gatherStartedAt = nil
        envelopeStartedAt = nil
        firedHops.removeAll()
        trigger = nil
        phase = .idle
    }
}
