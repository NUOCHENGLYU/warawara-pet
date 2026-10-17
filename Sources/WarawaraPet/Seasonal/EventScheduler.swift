import AppKit
import Foundation

/// Shared event scheduler for Phase 6B: holiday eligibility (priority
/// order), low-frequency daily micro-events, mutual exclusion, and
/// replay routing. The birthday event keeps its own coordinator but the
/// scheduler always defers to it (priority 0).
final class EventScheduler {
    let clock: BirthdayClock
    let persistence: SeasonalPersistence
    let policy: DailyEventPolicy
    private let appLaunchDate: Date

    weak var birthdayCoordinator: BirthdayEventCoordinator?

    /// Per-kind seasonal coordinators (one scene owner at a time).
    private(set) var coordinators: [SeasonalEventKind: SeasonalEventCoordinator] = [:]
    private var presenters: [SeasonalEventKind: SeasonalEventPresenter] = [:]
    private weak var windowController: PetWindowController?

    /// Injected busy-state checks from the app wiring.
    var isPetBusy: (() -> Bool)?
    var isBirthdayBlocking: (() -> Bool)?

    private var rng: any RandomSource = SystemRandomSource()
    private var lastEvaluation: Date?
    private var nextDailyEligibleAt: Date?

    /// Replay requests accepted before the app finishes launching.
    private var pendingReplayKinds: [SeasonalEventKind] = []

    init(
        clock: BirthdayClock = SystemBirthdayClock(),
        persistence: SeasonalPersistence = SeasonalPersistence(),
        policy: DailyEventPolicy = .default,
        appLaunchDate: Date = Date(),
        seededRNG: (any RandomSource)? = nil
    ) {
        self.clock = clock
        self.persistence = persistence
        self.policy = policy
        self.appLaunchDate = appLaunchDate
        if let seededRNG {
            rng = seededRNG
        }
    }

    func configure(
        windowController: PetWindowController,
        kinds: [SeasonalEventKind] = SeasonalEventKind.allCases
    ) {
        self.windowController = windowController
        for kind in kinds {
            let coordinator = SeasonalEventCoordinator(
                clock: clock,
                persistence: persistence,
                timing: .forKind(kind)
            )
            let presenter = SeasonalEventPresenter(
                windowController: windowController,
                coordinator: coordinator,
                store: .shared
            )
            coordinator.presenter = presenter
            coordinator.isPetBusy = { [weak self] in self?.isPetBusy?() ?? false }
            coordinator.completionObservers.append { [weak self] kind, trigger in
                self?.sceneCompleted(kind: kind, trigger: trigger)
            }
            coordinators[kind] = coordinator
            presenters[kind] = presenter
            EventReplayLog.presenterAttached(id: kind.replayArgument)
        }
    }

    // MARK: - Evaluation

    var isAnyEventRunning: Bool {
        if let birthdayCoordinator, birthdayCoordinator.isRunning { return true }
        return coordinators.values.contains(where: \.isRunning)
    }

    /// Called periodically (~1 Hz) by the app. Evaluates holiday
    /// eligibility then daily scheduling, always deferring to the
    /// birthday event.
    func tick() {
        let now = clock.now()
        if let last = lastEvaluation, now.timeIntervalSince(last) < 1 { return }
        lastEvaluation = now

        // Replays requested before wiring are consumed first.
        for kind in pendingReplayKinds {
            EventReplayLog.ready(id: kind.replayArgument)
            coordinators[kind]?.requestTrigger(kind, trigger: .replay)
        }
        pendingReplayKinds.removeAll()
        for coordinator in coordinators.values {
            coordinator.servicePendingTrigger()
            // THE playback clock: seasonal/daily scenes advance here.
            // (The birthday coordinator has its own advance loop.)
            coordinator.advance(at: now)
        }

        guard !(isBirthdayBlocking?() ?? false), !isAnyEventRunning else { return }

        // Holidays by priority.
        for kind in SeasonalEventKind.allCases.filter(\.isHoliday).sorted(by: { $0.priorityRank < $1.priorityRank }) {
            guard SeasonalEligibility.isEligible(kind, date: now, calendar: clock.calendar) else { continue }
            let year = SeasonalEligibility.occurrenceYear(for: kind, date: now, calendar: clock.calendar)
            guard !persistence.isCompleted(kind, occurrenceYear: year) else { continue }
            let coordinator = coordinators[kind]
            coordinator?.requestTrigger(kind, trigger: .automatic)
            coordinator?.servicePendingTrigger()
            break
        }
        guard !isAnyEventRunning else { return }

        // Daily micro-events.
        if let nextDailyEligibleAt, now < nextDailyEligibleAt { return }
        evaluateDaily(now: now)
    }

    private func evaluateDaily(now: Date) {
        let uptime = now.timeIntervalSince(appLaunchDate)
        let busy = (isPetBusy?() ?? false) || (isBirthdayBlocking?() ?? false)
        guard policy.maySchedule(
            now: now,
            calendar: clock.calendar,
            appUptime: max(uptime, 0),
            history: persistence.dailyHistory(),
            lastCompletion: persistence.lastDailyCompletion,
            isBusy: busy
        ) else {
            nextDailyEligibleAt = now.addingTimeInterval(10 * 60)
            return
        }
        guard let kind = policy.pickKind(
            now: now,
            history: persistence.dailyHistory(),
            using: &rng
        ) else {
            nextDailyEligibleAt = now.addingTimeInterval(30 * 60)
            return
        }
        let coordinator = coordinators[kind]
        coordinator?.requestTrigger(kind, trigger: .automatic)
        coordinator?.servicePendingTrigger()
        nextDailyEligibleAt = now.addingTimeInterval(policy.nextEvaluationDelay(using: &rng))
    }

    private func sceneCompleted(kind: SeasonalEventKind, trigger: SeasonalEventCoordinator.Trigger) {
        guard trigger == .automatic, !kind.isHoliday else { return }
        let now = clock.now()
        persistence.appendDailyRecord(SeasonalPersistence.DailyRecord(
            kind: kind.rawValue,
            dayKey: DailyEventPolicy.dayKey(for: now, calendar: clock.calendar),
            timestamp: now.timeIntervalSince1970
        ))
        persistence.markDailyCompleted(at: now.timeIntervalSince1970)
    }

    // MARK: - Replay

    func requestReplay(kind: SeasonalEventKind) {
        EventReplayLog.requested(id: kind.replayArgument)
        if let coordinator = coordinators[kind] {
            coordinator.requestTrigger(kind, trigger: .replay)
        } else {
            pendingReplayKinds.append(kind)
        }
    }
}
