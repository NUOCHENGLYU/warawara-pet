import Foundation

/// Phases shared by all seasonal + daily scenes. The birthday event
/// keeps its own richer coordinator; this one drives the smaller,
/// reusable performances.
enum SeasonalPhase: Equatable {
    case idle
    case noticing
    case approach
    case present
    case celebrate
    case depart
    case completed
    case cancelled
}

/// Per-kind timing (seconds). One scene owner at a time; all timings
/// centralized here.
struct SeasonalTiming {
    var noticeDuration: TimeInterval = 2.2
    var approachDuration: TimeInterval = 3.0
    var presentDuration: TimeInterval = 4.5
    var celebrateDuration: TimeInterval = 4.0
    var departDuration: TimeInterval = 2.5
    /// Hops at these offsets from the CELEBRATE start.
    var celebrationHopOffsets: [TimeInterval] = [0.4, 2.2]

    static func forKind(_ kind: SeasonalEventKind) -> SeasonalTiming {
        var timing = SeasonalTiming()
        switch kind {
        case .cny, .christmas:
            timing = SeasonalTiming(
                noticeDuration: 2.4, approachDuration: 3.4, presentDuration: 5.0,
                celebrateDuration: 5.0, departDuration: 3.0,
                celebrationHopOffsets: [0.5, 2.6]
            )
        case .newYear:
            timing = SeasonalTiming(
                noticeDuration: 2.0, approachDuration: 2.8, presentDuration: 3.5,
                celebrateDuration: 3.5, departDuration: 2.2,
                celebrationHopOffsets: [0.4, 1.8]
            )
        case .umbrella:
            timing = SeasonalTiming(
                noticeDuration: 1.8, approachDuration: 2.2, presentDuration: 5.0,
                celebrateDuration: 3.0, departDuration: 2.0,
                celebrationHopOffsets: []
            )
        case .hotCocoa:
            timing = SeasonalTiming(
                noticeDuration: 1.8, approachDuration: 2.2, presentDuration: 5.5,
                celebrateDuration: 3.0, departDuration: 2.0,
                celebrationHopOffsets: []
            )
        case .sprout:
            timing = SeasonalTiming(
                noticeDuration: 1.5, approachDuration: 1.8, presentDuration: 4.5,
                celebrateDuration: 2.5, departDuration: 1.8,
                celebrationHopOffsets: []
            )
        case .paperAirplane:
            timing = SeasonalTiming(
                noticeDuration: 1.2, approachDuration: 3.5, presentDuration: 1.5,
                celebrateDuration: 2.0, departDuration: 1.8,
                celebrationHopOffsets: []
            )
        }
        return timing
    }
}

/// UI realization contract for the shared seasonal scenes.
protocol SeasonalEventPresenting: AnyObject {
    func noticeScene()
    func presentProp()
    func settleProp()
    func celebrateScene()
    func departScene()
    func clearAttention()
}

/// Generic coordinator for seasonal and daily micro-events: eligibility
/// is evaluated by the scheduler; this owns phases, timing, completion
/// and cancellation for exactly one scene at a time.
final class SeasonalEventCoordinator {
    enum Trigger: Equatable { case automatic, replay }

    private(set) var kind: SeasonalEventKind?
    private(set) var phase: SeasonalPhase = .idle
    private(set) var trigger: Trigger?
    let timing: SeasonalTiming
    let clock: BirthdayClock
    let persistence: SeasonalPersistence
    weak var presenter: SeasonalEventPresenting?
    var isPetBusy: (() -> Bool)?
    /// Called when a scene reaches its recoverable completion (kind +
    /// trigger). The scheduler uses this for daily history.
    var onSceneCompleted: ((SeasonalEventKind, Trigger) -> Void)?

    private var startedAt: Date?
    private var celebrateStartedAt: Date?
    private var firedHops: Set<Int> = []
    private var pendingTrigger: Trigger?

    var isRunning: Bool { phase != .idle }

    init(
        clock: BirthdayClock = SystemBirthdayClock(),
        persistence: SeasonalPersistence = SeasonalPersistence(),
        timing: SeasonalTiming = .forKind(.umbrella)
    ) {
        self.clock = clock
        self.persistence = persistence
        self.timing = timing
    }

    // MARK: - Triggering

    func requestTrigger(_ kind: SeasonalEventKind, trigger: Trigger) {
        guard phase == .idle else { return }
        self.kind = kind
        pendingTrigger = trigger
    }

    func requestCancellation() {
        guard isRunning else { return }
        cancelEvent()
    }

    func servicePendingTrigger() {
        guard let pending = pendingTrigger, let kind else { return }
        if isPetBusy?() == true { return }
        pendingTrigger = nil
        begin(kind, trigger: pending)
    }

    private func begin(_ kind: SeasonalEventKind, trigger: Trigger) {
        guard phase == .idle else { return }
        self.kind = kind
        self.trigger = trigger
        startedAt = clock.now()
        celebrateStartedAt = nil
        firedHops.removeAll()
        phase = .noticing
        presenter?.noticeScene()
    }

    // MARK: - Advancing

    /// Advances the scene. Large elapsed jumps catch up through ALL
    /// pending phase transitions (bounded loop), so timers and tests
    /// agree on phase semantics.
    func advance(at now: Date) {
        guard let startedAt else { return }
        var safety = 0
        while safety < 10 {
            safety += 1
            let before = phase
            stepOnce(at: now, startedAt: startedAt)
            if phase == before { break }
        }
    }

    private func stepOnce(at now: Date, startedAt: Date) {
        let elapsed = now.timeIntervalSince(startedAt)
        switch phase {
        case .idle:
            return
        case .noticing:
            if elapsed >= timing.noticeDuration {
                phase = .approach
                presenter?.presentProp()
            }
        case .approach:
            if elapsed >= timing.noticeDuration + timing.approachDuration {
                phase = .present
                presenter?.settleProp()
            }
        case .present:
            if elapsed >= timing.noticeDuration + timing.approachDuration + timing.presentDuration {
                phase = .celebrate
                celebrateStartedAt = now
                presenter?.celebrateScene()
            }
        case .celebrate:
            guard let celebrateStartedAt else { return }
            let celebrateElapsed = now.timeIntervalSince(celebrateStartedAt)
            for (index, offset) in timing.celebrationHopOffsets.enumerated()
            where !firedHops.contains(index) && celebrateElapsed >= offset {
                firedHops.insert(index)
                presenter?.celebrateScene() // hop is a presenter cue
            }
            if celebrateElapsed >= timing.celebrateDuration {
                phase = .depart
                presenter?.departScene()
            }
        case .depart:
            if elapsed >= totalDuration {
                complete()
            }
        case .completed, .cancelled:
            return
        }
    }

    private var totalDuration: TimeInterval {
        timing.noticeDuration + timing.approachDuration + timing.presentDuration
            + timing.celebrateDuration + timing.departDuration
    }

    // MARK: - Completion / cancellation

    private func complete() {
        phase = .completed
        if let kind, trigger == .automatic, kind.isHoliday {
            persistence.markCompleted(kind, occurrenceYear: SeasonalEligibility.occurrenceYear(
                for: kind, date: clock.now(), calendar: clock.calendar
            ))
        }
        if let kind, let trigger {
            onSceneCompleted?(kind, trigger)
        }
        presenter?.clearAttention()
        reset()
    }

    private func cancelEvent() {
        presenter?.clearAttention()
        presenter?.departScene()
        phase = .cancelled
        reset()
    }

    private func reset() {
        startedAt = nil
        celebrateStartedAt = nil
        firedHops.removeAll()
        trigger = nil
        kind = nil
        phase = .idle
    }
}
