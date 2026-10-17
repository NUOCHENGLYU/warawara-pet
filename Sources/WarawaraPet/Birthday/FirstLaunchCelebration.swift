import Foundation

/// Once-only first-launch birthday surprise.
///
/// A GENUINELY fresh installation plays the birthday celebration on the
/// very first launch — even on October 18 or any other day — so the gift
/// survives a late opening. Rules:
/// - Existing installations are detected through legacy markers that
///   have always been written (position store, birthday persistence),
///   NOT merely by the absence of the new key.
/// - On October 17 the annual path owns the celebration; first-launch
///   only records completion (no duplicate surprise).
/// - Completion is persisted BEFORE playback, so interrupted playback
///   never replays the surprise on the next launch.
/// - Manual --replay-birthday never touches first-launch or annual
///   eligibility.
final class FirstLaunchCelebration {
    static let completedKey = "warawarapet.firstlaunch.celebrationCompleted"

    /// Keys written by every previously-used installation.
    static let legacyMarkers: [String] = [
        BirthdayPersistence.completedYearsKey,
        BirthdayPersistence.envelopeUnlockedKey,
        BirthdayPersistence.envelopeRetiredKey,
        "pet.position.x",
        "pet.position.y"
    ]

    private let coordinator: BirthdayEventCoordinator
    private let persistence: BirthdayPersistence
    private weak var windowController: PetWindowController?
    private let clock: BirthdayClock
    private let defaults: UserDefaults
    private var retryTimer: Timer?
    private var attempts = 0
    private let maxAttempts = 14
    /// Called when the celebration requests/retracts the birthday hat.
    var setCelebrationHat: ((Bool) -> Void)?

    init(
        coordinator: BirthdayEventCoordinator,
        persistence: BirthdayPersistence = BirthdayPersistence(),
        windowController: PetWindowController,
        clock: BirthdayClock = SystemBirthdayClock(),
        defaults: UserDefaults = .standard
    ) {
        self.coordinator = coordinator
        self.persistence = persistence
        self.windowController = windowController
        self.clock = clock
        self.defaults = defaults
    }

    func start() {
        evaluate()
    }

    private func evaluate() {
        guard !defaults.bool(forKey: Self.completedKey) else { return }
        if hasLegacyInstallMarker() {
            // Existing installation migration: never treat as fresh.
            defaults.set(true, forKey: Self.completedKey)
            EventDiagnostics.firstLaunch("EXISTING_INSTALL_MIGRATED")
            return
        }
        let now = clock.now()
        if BirthdayDateMath.isBirthday(date: now, calendar: clock.calendar) {
            // The annual October 17 celebration owns today; record
            // completion so the surprise never fires later this year.
            defaults.set(true, forKey: Self.completedKey)
            EventDiagnostics.firstLaunch("BIRTHDAY_TODAY_DEFERRED_TO_ANNUAL")
            return
        }
        attemptTrigger()
    }

    private func hasLegacyInstallMarker() -> Bool {
        Self.legacyMarkers.contains { defaults.object(forKey: $0) != nil }
    }

    private func attemptTrigger() {
        attempts += 1
        guard !(windowController?.isPetDragging ?? false),
              !(windowController?.isPetSleeping ?? false),
              !coordinator.isRunning else {
            scheduleRetry()
            return
        }
        // Persist completion BEFORE playback: interrupted playback must
        // never replay the surprise.
        defaults.set(true, forKey: Self.completedKey)
        EventDiagnostics.firstLaunch("CELEBRATION_BEGAN")
        setCelebrationHat?(true)
        coordinator.requestTrigger(.replay)
        watchForCelebrationEnd()
    }

    private func scheduleRetry() {
        guard attempts < maxAttempts else {
            EventDiagnostics.firstLaunch("DEFERRED_TIMEOUT")
            return
        }
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.attemptTrigger()
        }
    }

    /// Remove the birthday hat once the surprise celebration finishes
    /// (graceful crossfade is handled by the wearable controller).
    private func watchForCelebrationEnd() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.checkCelebrationEnded()
        }
    }

    /// Internal check (also testable): the hat is removed only AFTER the
    /// celebration was observed running — a deferred pending trigger must
    /// never count as "ended".
    func checkCelebrationEnded() {
        guard sawCelebrationRunning else {
            if coordinator.isRunning {
                sawCelebrationRunning = true
            }
            return
        }
        guard !coordinator.isRunning else { return }
        sawCelebrationRunning = false
        retryTimer?.invalidate()
        retryTimer = nil
        setCelebrationHat?(false)
        EventDiagnostics.firstLaunch("CELEBRATION_ENDED_HAT_REMOVED")
    }

    private var sawCelebrationRunning = false
}
