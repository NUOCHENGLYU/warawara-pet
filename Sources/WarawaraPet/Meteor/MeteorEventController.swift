import CoreGraphics
import Foundation

/// Meteor phases. The pet notices, tracks the flight until complete
/// disappearance, makes a wish (eyes closed), then celebrates.
enum MeteorPhase: Equatable {
    case idle
    case noticing
    case flight
    /// The meteor has fully left the display; the pet keeps gazing
    /// toward the exit briefly.
    case departed
    /// Eyes closed, a quiet wish (constant duration).
    case wishing
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

/// Arc-length sampler over a trajectory: maps a uniform 0...1 arc-length
/// fraction to the trajectory parameter so screen-space speed is nearly
/// constant (the raw cubic Bézier accelerates/decelerates visibly).
struct MeteorTrajectorySampler {
    let trajectory: MeteorTrajectory
    private let parameters: [CGFloat]
    private let cumulative: [CGFloat]
    private let totalLength: CGFloat

    init(trajectory: MeteorTrajectory, samples: Int = 256) {
        self.trajectory = trajectory
        var params: [CGFloat] = []
        var lengths: [CGFloat] = []
        params.reserveCapacity(samples + 1)
        lengths.reserveCapacity(samples + 1)
        var previous = trajectory.position(at: 0)
        var total: CGFloat = 0
        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let p = trajectory.position(at: t)
            if index > 0 {
                total += hypot(p.x - previous.x, p.y - previous.y)
            }
            params.append(t)
            lengths.append(total)
            previous = p
        }
        parameters = params
        cumulative = lengths
        totalLength = total
    }

    /// Bézier parameter t for an arc-length fraction s in 0...1.
    func parameter(for s: CGFloat) -> CGFloat {
        guard totalLength > 0 else { return 0 }
        let target = min(max(s, 0), 1) * totalLength
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulative[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low > 0 else { return parameters[0] }
        let segment = cumulative[low] - cumulative[low - 1]
        guard segment > 0 else { return parameters[low] }
        let fraction = (target - cumulative[low - 1]) / segment
        return parameters[low - 1] + (parameters[low] - parameters[low - 1]) * fraction
    }

    func position(atArcLength s: CGFloat) -> CGPoint {
        trajectory.position(at: parameter(for: s))
    }

    func heading(atArcLength s: CGFloat) -> CGFloat {
        trajectory.heading(at: parameter(for: s))
    }
}

/// Pure nightly meteor scheduling: EVERY day at the user's LOCAL 22:17,
/// at most one automatic meteor per local date, with a 90-second grace
/// window that absorbs scheduling jitter and short conflicts.
///
/// - No probability, no random showtime — the time is fixed at 22:17:00.
/// - The local date is resolved with the given calendar (production uses
///   `Calendar.autoupdatingCurrent`), so timezone changes, DST and
///   midnight crossings follow the system's local calendar.
/// - Lid-closed sleep is respected: the Mac is never woken for the show.
///   If the machine is awake during the 90 s grace window the meteor can
///   still run; past 22:18:30 the night is skipped (recorded once, so a
///   later clock rollback can never re-fire the same local date).
/// - Busy/birthday conflicts defer within the grace window only; they
///   can never push the show to 23:00 or the next day.
struct MeteorNightlyScheduler {
    static let fireHour = 22
    static let fireMinute = 17
    /// Grace window after 22:17:00 during which a late tick still fires.
    static let graceSeconds: TimeInterval = 90

    /// Returns true when the automatic meteor should begin RIGHT NOW.
    func evaluate(
        now: Date,
        calendar: Calendar,
        persistence: MeteorPersistence,
        busy: Bool,
        birthdayBlocking: Bool
    ) -> Bool {
        let fire = Self.fireDate(forDayContaining: now, calendar: calendar)
        guard now >= fire else { return false }
        let dayKey = MeteorPersistence.nightKey(now, calendar: calendar)
        guard !persistence.automaticFired(forKey: dayKey),
              !persistence.automaticSkipped(forKey: dayKey) else { return false }
        let deadline = fire.addingTimeInterval(Self.graceSeconds)
        if now > deadline {
            // The window is genuinely past (sleep, late launch, forward
            // clock jump): record the skip once per local date so a
            // backward clock adjustment can never re-fire tonight.
            persistence.markAutomaticSkipped(forKey: dayKey)
            return false
        }
        guard !busy, !birthdayBlocking else { return false }
        // Mark at the moment of firing: the caller begins the show in
        // the same tick, so the record is never "fired without playing".
        persistence.markAutomaticFired(forKey: dayKey)
        return true
    }

    /// Today's local 22:17:00, built from calendar components so DST
    /// transitions and timezone changes resolve through the local
    /// calendar (never a fixed-seconds arithmetic).
    static func fireDate(forDayContaining date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = Self.fireHour
        components.minute = Self.fireMinute
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? date
    }
}

/// Pure meteor event coordinator: eligibility, phases, timing and the
/// fixed world-space trajectory.
///
/// TIMEBASE CONTRACT: the 4 Hz scheduler owns PHASES and eligibility;
/// the continuous renderer owns frame-by-frame position. Both share ONE
/// monotonic clock (`flightStartUptime`) so progress and phase
/// boundaries can never disagree. The controller never moves the panel.
final class MeteorEventController {
    enum Trigger: Equatable { case automatic, replay }

    struct Timing {
        var noticeDuration: TimeInterval = 1.2
        var flightDuration: TimeInterval = 6.5
        /// Gaze-hold after the meteor fully exits.
        var departedDuration: TimeInterval = 0.9
        /// The wish: eyes closed. Constant, 2.5-4 s per spec.
        var wishingDuration: TimeInterval = 3.0
        var celebrationDuration: TimeInterval = 2.0
    }

    let timing: Timing
    let clock: BirthdayClock
    let persistence: MeteorPersistence
    private let nightly: MeteorNightlyScheduler

    /// Injectable monotonic clock (host uptime in production); tests
    /// control this to verify the single-timebase contract.
    var monotonicNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private(set) var phase: MeteorPhase = .idle
    private(set) var trigger: Trigger?
    private(set) var trajectory: MeteorTrajectory?
    private var startedAt: Date?
    /// The canonical flight origin on the monotonic clock.
    private var flightStartUptime: TimeInterval?
    private var pendingTrigger: Trigger?

    weak var presenter: MeteorEventPresenting?
    var isPetBusy: (() -> Bool)?
    var isBirthdayBlocking: (() -> Bool)?
    var completionObservers: [(Trigger) -> Void] = []

    var isRunning: Bool { phase != .idle }

    init(
        clock: BirthdayClock = SystemBirthdayClock(),
        persistence: MeteorPersistence = MeteorPersistence(),
        timing: Timing = Timing(),
        nightly: MeteorNightlyScheduler = MeteorNightlyScheduler()
    ) {
        self.clock = clock
        self.persistence = persistence
        self.timing = timing
        self.nightly = nightly
    }

    // MARK: - Single canonical flight progress (renderer authority)

    /// Normalized flight progress from the monotonic clock (nil outside
    /// the flight phase). The ONLY source of frame-by-frame position.
    func flightProgress(atUptime uptime: TimeInterval) -> CGFloat? {
        guard phase == .flight, let flightStartUptime else { return nil }
        let elapsed = uptime - flightStartUptime
        return CGFloat(min(max(elapsed / timing.flightDuration, 0), 1))
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
        // CI smoke mode is deterministic: it bypasses the birthday/busy
        // blocking so the packaged replay always runs to completion.
        if !EventDiagnostics.smokeMode,
           isPetBusy?() == true || isBirthdayBlocking?() == true {
            return
        }
        pendingTrigger = nil
        begin(pending)
    }

    private func begin(_ trigger: Trigger) {
        guard phase == .idle else { return }
        self.trigger = trigger
        startedAt = clock.now()
        flightStartUptime = nil
        phase = .noticing
        EventDiagnostics.meteor("STARTED trigger=\(trigger)")
        presenter?.noticeScene()
    }

    // MARK: - Advancing (phases only — never panel movement)

    func advance(at now: Date) {
        guard let startedAt else { return }
        var safety = 0
        while safety < 12 {
            safety += 1
            let before = phase
            stepOnce(at: now, startedAt: startedAt)
            if phase == before { break }
        }
    }

    private func stepOnce(at now: Date, startedAt: Date) {
        let dateElapsed = now.timeIntervalSince(startedAt)
        switch phase {
        case .idle:
            return
        case .noticing:
            if dateElapsed >= timing.noticeDuration {
                phase = .flight
                // The shared origin: phases and the renderer both derive
                // flight progress from THIS monotonic timestamp.
                flightStartUptime = monotonicNow()
                let visible = presenter?.activeVisibleFrame ?? .zero
                trajectory = MeteorTrajectory.fixed(in: visible)
                presenter?.flightDidBegin(trajectory: trajectory!)
                EventDiagnostics.meteor("FLIGHT_BEGAN")
            }
        case .flight:
            // Phase boundary on the SAME monotonic timeline as the
            // renderer: the flight ends exactly when progress reaches 1.
            guard let flightStartUptime else { return }
            let flightElapsed = monotonicNow() - flightStartUptime
            if flightElapsed >= timing.flightDuration {
                phase = .departed
                presenter?.meteorDeparted()
                EventDiagnostics.meteor("DEPARTED")
            }
        case .departed:
            guard let flightStartUptime else { return }
            let afterFlight = monotonicNow() - flightStartUptime - timing.flightDuration
            if afterFlight >= timing.departedDuration {
                phase = .wishing
                presenter?.wishingDidBegin()
                EventDiagnostics.meteor("WISHING_BEGAN")
            }
        case .wishing:
            guard let flightStartUptime else { return }
            let afterDepart = monotonicNow() - flightStartUptime
                - timing.flightDuration - timing.departedDuration
            if afterDepart >= timing.wishingDuration {
                phase = .celebration
                presenter?.celebrationDidBegin()
                EventDiagnostics.meteor("CELEBRATION_BEGAN")
            }
        case .celebration:
            guard let flightStartUptime else { return }
            let afterWish = monotonicNow() - flightStartUptime
                - timing.flightDuration - timing.departedDuration - timing.wishingDuration
            if afterWish >= timing.celebrationDuration {
                complete(now: now)
            }
        case .completed, .cancelled:
            return
        }
    }

    private func complete(now: Date) {
        phase = .completed
        presenter?.cleanup()
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
        flightStartUptime = nil
        trajectory = nil
        trigger = nil
        phase = .idle
    }

    /// App tick (4 Hz): service pending replays, advance phases, and
    /// evaluate the fixed daily 22:17 automatic schedule.
    func tick() {
        let now = clock.now()
        servicePendingTrigger()
        advance(at: now)
        guard phase == .idle else { return }
        let shouldFire = nightly.evaluate(
            now: now,
            calendar: clock.calendar,
            persistence: persistence,
            busy: isPetBusy?() ?? false,
            birthdayBlocking: isBirthdayBlocking?() ?? false
        )
        if shouldFire {
            requestTrigger(.automatic)
            servicePendingTrigger()
        }
    }
}

/// The presenter side of the meteor event. The controller never moves
/// the panel: the presenter's display-synced renderer is the sole
/// position authority.
protocol MeteorEventPresenting: AnyObject {
    /// The display the meteor will fly across (from the pet's screen).
    var activeVisibleFrame: CGRect { get }
    func noticeScene()
    func flightDidBegin(trajectory: MeteorTrajectory)
    func meteorDeparted()
    func wishingDidBegin()
    func celebrationDidBegin()
    func cleanup()
}

/// UserDefaults persistence for the daily automatic meteor. The new
/// fixed 22:17 schedule uses its OWN namespace (…daily22_17…) so legacy
/// random-night records from older builds can never influence it.
struct MeteorPersistence {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Local-date key ("YYYY-M-D") for the day a given instant belongs
    /// to, resolved with the provided calendar (production passes the
    /// autoupdating local calendar).
    static func nightKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func dailyKey(_ suffix: String, dayKey: String) -> String {
        "warawarapet.meteor.daily22_17.\(dayKey).\(suffix)"
    }

    /// True once the automatic meteor fired for this local date.
    func automaticFired(forKey dayKey: String) -> Bool {
        defaults.bool(forKey: dailyKey("fired", dayKey: dayKey))
    }

    /// Records the automatic fire for this local date. Called ONLY at
    /// the moment the show begins, so a record can never be "fired
    /// without playing".
    func markAutomaticFired(forKey dayKey: String) {
        defaults.set(true, forKey: dailyKey("fired", dayKey: dayKey))
    }

    /// True once the local date's window was recorded as missed.
    func automaticSkipped(forKey dayKey: String) -> Bool {
        defaults.bool(forKey: dailyKey("skipped", dayKey: dayKey))
    }

    /// Records that the grace window passed without a show (sleep, late
    /// launch, forward clock jump). Guards against clock rollbacks
    /// re-firing the same local date.
    func markAutomaticSkipped(forKey dayKey: String) {
        defaults.set(true, forKey: dailyKey("skipped", dayKey: dayKey))
    }
}
