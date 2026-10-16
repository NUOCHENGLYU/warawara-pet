import Foundation

/// Centralized, testable policy for low-frequency daily micro-events.
/// All timing constants live here; the scheduler only evaluates.
struct DailyEventPolicy {
    /// App must be up this long before the first daily event.
    var firstEventDelay: TimeInterval = 20 * 60
    /// Minimum gap between completed automatic daily events.
    var globalCooldown: TimeInterval = 120 * 60
    /// Optional randomized extra delay range.
    var extraRandomDelayRange: ClosedRange<TimeInterval> = 0...(60 * 60)
    /// Maximum automatic daily events per local calendar day.
    var maxPerDay = 2
    /// Quiet hours (local hour-of-day, inclusive start, exclusive end).
    var quietHoursStart = 23
    var quietHoursEnd = 8
    /// Same-type avoidance window.
    var recentTypeAvoidance: TimeInterval = 24 * 60 * 60

    static let `default` = DailyEventPolicy()

    /// Local day key yyyy-MM-dd.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// True when the current local hour is inside the quiet window.
    func isQuietHour(for date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if quietHoursStart >= quietHoursEnd {
            // Window crosses midnight (23:00 -> 08:00).
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
        return hour >= quietHoursStart && hour < quietHoursEnd
    }

    /// Whether a daily event may be scheduled right now.
    func maySchedule(
        now: Date,
        calendar: Calendar,
        appUptime: TimeInterval,
        history: [SeasonalPersistence.DailyRecord],
        lastCompletion: TimeInterval?,
        isBusy: Bool
    ) -> Bool {
        guard !isBusy else { return false }
        guard appUptime >= firstEventDelay else { return false }
        guard !isQuietHour(for: now, calendar: calendar) else { return false }
        if let lastCompletion, now.timeIntervalSince1970 - lastCompletion < globalCooldown {
            return false
        }
        let today = Self.dayKey(for: now, calendar: calendar)
        let todayCount = history.filter { $0.dayKey == today }.count
        guard todayCount < maxPerDay else { return false }
        return true
    }

    /// Weighted random choice avoiding recently used kinds when
    /// alternatives exist. Deterministic with an injected RNG.
    func pickKind(
        now: Date,
        history: [SeasonalPersistence.DailyRecord],
        using rng: inout some RandomSource
    ) -> SeasonalEventKind? {
        let dailyKinds: [SeasonalEventKind] = [.umbrella, .hotCocoa, .sprout, .paperAirplane]
        let recentKinds = Set(history.filter {
            now.timeIntervalSince1970 - $0.timestamp < recentTypeAvoidance
        }.map(\.kind))
        let fresh = dailyKinds.filter { !recentKinds.contains($0.rawValue) }
        let pool = fresh.isEmpty ? dailyKinds : fresh
        let index = Int(rng.nextUnit() * Double(pool.count))
        return pool[min(index, pool.count - 1)]
    }

    /// The delay until the next daily evaluation should happen.
    func nextEvaluationDelay(using rng: inout some RandomSource) -> TimeInterval {
        globalCooldown + RandomBounds.randomDelay(in: extraRandomDelayRange, using: &rng)
    }
}
