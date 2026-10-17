import CoreGraphics
import Foundation

/// Meteor phases. The pet notices, tracks the flight until complete
/// disappearance, then celebrates.
enum MeteorPhase: Equatable {
    case idle
    case noticing
    case flight
    case celebration
    case completed
    case cancelled
}

/// Pure world-space meteor trajectory: entry and exit positions are
/// fixed BEYOND the display edges, so the meteor always disappears
/// completely — the panel can never leave a frozen sprite at the edge.
struct MeteorTrajectory: Equatable {
    let entry: CGPoint
    let exit: CGPoint
    let control1: CGPoint
    let control2: CGPoint

    /// Diagonal flight: enters top-left-ish beyond the edge, exits
    /// bottom-right-ish beyond the opposite edge, with a gentle arc.
    static func fixed(in visibleFrame: CGRect) -> MeteorTrajectory {
        let entry = CGPoint(x: visibleFrame.minX - 150, y: visibleFrame.maxY * 0.78)
        let exit = CGPoint(x: visibleFrame.maxX + 170, y: visibleFrame.maxY * 0.26)
        let control1 = CGPoint(x: visibleFrame.minX + visibleFrame.width * 0.18,
                               y: visibleFrame.maxY * 0.92)
        let control2 = CGPoint(x: visibleFrame.minX + visibleFrame.width * 0.62,
                               y: visibleFrame.maxY * 0.48)
        return MeteorTrajectory(entry: entry, exit: exit, control1: control1, control2: control2)
    }

    func position(at t: CGFloat) -> CGPoint {
        let x = min(max(t, 0), 1)
        let u = 1 - x
        let a = u * u * u
        let b = 3 * u * u * x
        let c = 3 * u * x * x
        let d = x * x * x
        return CGPoint(
            x: a * entry.x + b * control1.x + c * control2.x + d * exit.x,
            y: a * entry.y + b * control1.y + c * control2.y + d * exit.y
        )
    }

    /// Heading in radians (screen coords, y-up).
    func heading(at t: CGFloat) -> CGFloat {
        let delta: CGFloat = 0.001
        let p0 = position(at: max(t - delta, 0))
        let p1 = position(at: min(t + delta, 1))
        return atan2(p1.y - p0.y, p1.x - p0.x)
    }
}

/// Pure meteor event coordinator: eligibility, phases, timing and the
/// fixed world-space trajectory. The presenter renders it.
final class MeteorEventController {
    enum Trigger: Equatable { case automatic, replay }

    struct Timing {
        var noticeDuration: TimeInterval = 1.2
        var flightDuration: TimeInterval = 6.5
        var celebrationDuration: TimeInterval = 2.0
        /// Quiet hours: no automatic meteors between 23:00 and 08:00.
        var quietHourStart = 23
        var quietHourEnd = 8
        /// Automatic scheduling limits.
        var cooldown: TimeInterval = 45 * 60
        var maxPerDay = 2
    }

    let timing: Timing
    let clock: BirthdayClock
    let persistence: MeteorPersistence

    private(set) var phase: MeteorPhase = .idle
    private(set) var trigger: Trigger?
    private(set) var trajectory: MeteorTrajectory?
    private var startedAt: Date?
    private var flightStartAt: Date?
    private var pendingTrigger: Trigger?

    weak var presenter: MeteorEventPresenting?
    var isPetBusy: (() -> Bool)?
    var isBirthdayBlocking: (() -> Bool)?
    var completionObservers: [(Trigger) -> Void] = []

    var isRunning: Bool { phase != .idle }

    /// Flight start time, exposed for the presenter's 30 Hz render loop.
    var flightStartedAt: Date? { flightStartAt }

    /// Normalized flight progress (nil outside the flight phase).
    func flightProgress(at now: Date) -> CGFloat? {
        guard phase == .flight, let flightStartAt else { return nil }
        return CGFloat(min(max(now.timeIntervalSince(flightStartAt) / timing.flightDuration, 0), 1))
    }

    init(
        clock: BirthdayClock = SystemBirthdayClock(),
        persistence: MeteorPersistence = MeteorPersistence(),
        timing: Timing = Timing()
    ) {
        self.clock = clock
        self.persistence = persistence
        self.timing = timing
    }

    // MARK: - Triggering

    func requestTrigger(_ trigger: Trigger) {
        guard phase == .idle else {
            EventDiagnostics.meteor("REJECTED_BUSY")
            return
        }
        pendingTrigger = trigger
    }

    func servicePendingTrigger() {
        guard let pending = pendingTrigger else { return }
        if isPetBusy?() == true || isBirthdayBlocking?() == true {
            return
        }
        pendingTrigger = nil
        begin(pending)
    }

    /// Automatic eligibility: cooldown, daily cap, quiet hours.
    func shouldTriggerAutomatically(now: Date) -> Bool {
        guard !(isPetBusy?() ?? false), !(isBirthdayBlocking?() ?? false) else { return false }
        let calendar = clock.calendar
        let hour = calendar.component(.hour, from: now)
        if timing.quietHourEnd <= timing.quietHourStart {
            // Overnight quiet window.
            if hour >= timing.quietHourStart || hour < timing.quietHourEnd { return false }
        } else if hour >= timing.quietHourStart || hour < timing.quietHourEnd {
            return false
        }
        guard now.timeIntervalSince(persistence.lastAutomaticDate ?? .distantPast) >= timing.cooldown else {
            return false
        }
        let dayKey = MeteorPersistence.dayKey(now, calendar: calendar)
        guard persistence.count(forDayKey: dayKey) < timing.maxPerDay else { return false }
        return true
    }

    private func begin(_ trigger: Trigger) {
        guard phase == .idle else { return }
        self.trigger = trigger
        startedAt = clock.now()
        flightStartAt = nil
        phase = .noticing
        EventDiagnostics.meteor("STARTED trigger=\(trigger)")
        presenter?.noticeScene()
    }

    // MARK: - Advancing

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
                phase = .flight
                flightStartAt = now
                let visible = presenter?.activeVisibleFrame ?? .zero
                trajectory = MeteorTrajectory.fixed(in: visible)
                presenter?.flightDidBegin(trajectory: trajectory!)
                EventDiagnostics.meteor("FLIGHT_BEGAN")
            }
        case .flight:
            // Flight progress is anchored on TOTAL elapsed time so the
            // catch-up loop can sweep the whole flight in one pass (the
            // presenter's 30 Hz loop still uses flightStartAt in real
            // time).
            let flightElapsed = now.timeIntervalSince(startedAt) - timing.noticeDuration
            let progress = CGFloat(min(max(flightElapsed / timing.flightDuration, 0), 1))
            presenter?.flightFrame(progress: progress, at: now)
            if flightElapsed >= timing.flightDuration {
                phase = .celebration
                presenter?.meteorDeparted()
                EventDiagnostics.meteor("DEPARTED")
            }        case .celebration:
            if elapsed >= timing.noticeDuration + timing.flightDuration + timing.celebrationDuration {
                complete(now: now)
            }
        case .completed, .cancelled:
            return
        }
    }

    private func complete(now: Date) {
        phase = .completed
        presenter?.cleanup()
        if trigger == .automatic {
            persistence.recordAutomatic(at: now, calendar: clock.calendar)
        }
        // The marker must be emitted BEFORE observers: smoke observers
        // may terminate the process.
        EventDiagnostics.meteor("COMPLETED")
        for observer in completionObservers {
            observer(trigger ?? .replay)
        }
        reset()
    }

    func cancel() {
        guard isRunning else { return }
        presenter?.cleanup()
        phase = .cancelled
        EventDiagnostics.meteor("CANCELLED")
        reset()
    }

    private func reset() {
        startedAt = nil
        flightStartAt = nil
        trajectory = nil
        trigger = nil
        phase = .idle
    }

    /// App tick: service pending replays, advance playback, and evaluate
    /// automatic triggering on the same cadence as the birthday event.
    func tick() {
        let now = clock.now()
        servicePendingTrigger()
        advance(at: now)
        guard phase == .idle else { return }
        if shouldTriggerAutomatically(now: now) {
            requestTrigger(.automatic)
            servicePendingTrigger()
        }
    }
}

/// The presenter side of the meteor event.
protocol MeteorEventPresenting: AnyObject {
    /// The display the meteor will fly across (from the pet's screen).
    var activeVisibleFrame: CGRect { get }
    func noticeScene()
    func flightDidBegin(trajectory: MeteorTrajectory)
    func flightFrame(progress: CGFloat, at now: Date)
    func meteorDeparted()
    func cleanup()
}

/// UserDefaults persistence for automatic meteor scheduling.
struct MeteorPersistence {
    static let lastKey = "warawarapet.meteor.lastAutomatic"
    static let dayKeyPrefix = "warawarapet.meteor.day."
    static let countKeyPrefix = "warawarapet.meteor.count."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastAutomaticDate: Date? {
        guard let interval = defaults.object(forKey: Self.lastKey) as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func count(forDayKey key: String) -> Int {
        defaults.integer(forKey: Self.countKeyPrefix + key)
    }

    func recordAutomatic(at date: Date, calendar: Calendar) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastKey)
        let key = Self.dayKey(date, calendar: calendar)
        defaults.set(count(forDayKey: key) + 1, forKey: Self.countKeyPrefix + key)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
