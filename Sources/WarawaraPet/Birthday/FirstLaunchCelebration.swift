import Foundation

/// Explicit first-launch celebration state machine.
///
/// States are persisted under ONE key owned by this machine — fresh
/// detection never depends on unrelated keys:
///
/// - `fresh`     (key absent): never celebrated on this install.
/// - `pending`   celebration owed: either deferred (busy), interrupted
///               before it started, or the launch day IS October 17 (the
///               annual event owns the day; the machine watches it).
/// - `running`   celebration observed running (persisted at start).
/// - `completed` celebration observed finishing.
///
/// Recovery rules:
/// - `fresh` at launch -> request the surprise (any date). If busy,
///   stay `fresh`/`pending` and keep retrying.
/// - `pending` at launch -> if not October 17, request it again
///   (recovers interrupted pending). On October 17, wait for the annual
///   event and just watch it.
/// - `running` at launch -> the previous session was interrupted mid-
///   celebration: safely replay it.
/// - `completed` -> never again. Manual --replay-birthday is unaffected.
enum FirstLaunchState: String {
    case fresh
    case pending
    case running
    case completed

    static let key = "warawarapet.firstlaunch.state"
    /// The previous build's boolean completion marker (our own key
    /// only): migrate it, never anything unrelated.
    static let legacyCompletedKey = "warawarapet.firstlaunch.celebrationCompleted"

    static func load(defaults: UserDefaults) -> FirstLaunchState {
        if defaults.bool(forKey: legacyCompletedKey) {
            // Migration from the previous single-key build.
            defaults.removeObject(forKey: legacyCompletedKey)
            defaults.set(FirstLaunchState.completed.rawValue, forKey: key)
            return .completed
        }
        if let raw = defaults.string(forKey: key), let state = FirstLaunchState(rawValue: raw) {
            return state
        }
        return .fresh
    }

    func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.key)
    }

    /// Development-only reset (--debug-reset-first-launch).
    static func resetForDebugging(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyCompletedKey)
    }
}

/// Non-destructive inspection of the REAL profile's first-launch
/// decision (--diagnose-first-launch). Never writes anything.
enum FirstLaunchDiagnosis {
    static func run(defaults: UserDefaults = .standard) {
        let state = FirstLaunchState.load(defaults: defaults)
        EventDiagnostics.emit("FIRST_LAUNCH_PROFILE bundle=\(Bundle.main.bundleIdentifier ?? "-") suite=\(defaults == .standard ? "standard" : "custom")")
        EventDiagnostics.emit("FIRST_LAUNCH_LEGACY_STATE present=\(defaults.object(forKey: FirstLaunchState.legacyCompletedKey) != nil)")
        EventDiagnostics.emit("FIRST_LAUNCH_ELIGIBLE \(state == .fresh)")
        EventDiagnostics.emit("FIRST_LAUNCH_\(state.rawValue.uppercased())")
        EventDiagnostics.emit("FIRST_LAUNCH_PET_POSITION present=\(defaults.object(forKey: "pet.position.x") != nil)")
        let clock = SystemBirthdayClock()
        EventDiagnostics.emit("FIRST_LAUNCH_TODAY_IS_BIRTHDAY \(BirthdayDateMath.isBirthday(date: clock.now(), calendar: clock.calendar))")
        if state == .fresh {
            EventDiagnostics.emit("FIRST_LAUNCH_DECISION play-on-next-normal-launch")
        } else if state == .pending {
            EventDiagnostics.emit("FIRST_LAUNCH_DECISION resume-pending")
        } else if state == .running {
            EventDiagnostics.emit("FIRST_LAUNCH_DECISION replay-interrupted")
        } else {
            EventDiagnostics.emit("FIRST_LAUNCH_DECISION already-completed")
        }
    }
}

final class FirstLaunchCelebration {
    private let coordinator: BirthdayEventCoordinator
    private weak var windowController: PetWindowController?
    private let clock: BirthdayClock
    private let defaults: UserDefaults
    private var timer: Timer?
    private var attempts = 0
    private let maxAttempts = 14
    private var state: FirstLaunchState = .fresh
    private var sawCelebrationRunningThisSession = false

    init(
        coordinator: BirthdayEventCoordinator,
        windowController: PetWindowController,
        clock: BirthdayClock = SystemBirthdayClock(),
        defaults: UserDefaults = .standard
    ) {
        self.coordinator = coordinator
        self.windowController = windowController
        self.clock = clock
        self.defaults = defaults
    }

    func start() {
        state = FirstLaunchState.load(defaults: defaults)
        evaluate()
        // A 1 Hz safety net catches the running->completed transition
        // even when the celebration ends without our watch timer.
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    /// Single deterministic evaluation step (also unit-testable).
    func evaluate() {
        let now = clock.now()
        let isBirthday = BirthdayDateMath.isBirthday(date: now, calendar: clock.calendar)
        let busy = (windowController?.isPetDragging ?? false)
            || (windowController?.isPetSleeping ?? false)

        switch state {
        case .fresh:
            if coordinator.isRunning {
                // An event (annual or replay) is already playing: watch it.
                transition(to: .running)
            } else if busy {
                // Never request while the pet is busy; stay fresh and the
                // periodic evaluation retries.
                EventDiagnostics.firstLaunch("SUPPRESSED reason=pet-busy")
            } else if isBirthday {
                // October 17: the annual event owns today. Watch it and
                // never double-trigger.
                transition(to: .pending)
                requestTriggerIfNeeded()
            } else {
                // Genuinely fresh, any other day: the surprise plays now.
                transition(to: .pending)
                requestTriggerIfNeeded()
            }
        case .pending:
            if coordinator.isRunning {
                transition(to: .running)
            } else if !isBirthday && !busy {
                // Interrupted/deferred pending: recover with a safe replay.
                requestTriggerIfNeeded()
            } else if busy {
                EventDiagnostics.firstLaunch("SUPPRESSED reason=pet-busy")
            }
        case .running:
            if coordinator.isRunning {
                sawCelebrationRunningThisSession = true
            } else if sawCelebrationRunningThisSession {
                // The celebration finished in THIS session.
                transition(to: .completed)
            } else {
                // The previous session was interrupted mid-celebration:
                // safely replay it.
                requestTriggerIfNeeded()
            }
        case .completed:
            break
        }

        EventDiagnostics.firstLaunch("STATE_\(state.rawValue.uppercased())")
    }

    private func requestTriggerIfNeeded() {
        guard !coordinator.isRunning else { return }
        guard attempts < maxAttempts else {
            EventDiagnostics.firstLaunch("SUPPRESSED reason=attempts-exhausted")
            return
        }
        attempts += 1
        // The trigger is pending until the birthday tick services it;
        // evaluate() observes isRunning and advances the state machine.
        coordinator.requestTrigger(.replay)
        EventDiagnostics.firstLaunch("PENDING")
    }

    private func transition(to newState: FirstLaunchState) {
        guard state != newState else { return }
        state = newState
        state.save(to: defaults)
        if newState == .completed {
            EventDiagnostics.firstLaunch("COMPLETED")
        }
        if newState == .running {
            sawCelebrationRunningThisSession = true
            EventDiagnostics.firstLaunch("STARTED")
        }
    }
}
