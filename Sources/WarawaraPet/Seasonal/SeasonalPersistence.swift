import Foundation

/// Persistence for seasonal holidays (once per occurrence) and daily
/// micro-event history (cooldowns, per-day caps, recent-type avoidance).
struct SeasonalPersistence {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Holiday annual completion

    private func holidayKey(_ kind: SeasonalEventKind) -> String {
        "warawarapet.seasonal.completedYears.\(kind.rawValue)"
    }

    func completedOccurrenceYears(for kind: SeasonalEventKind) -> [Int] {
        defaults.array(forKey: holidayKey(kind)) as? [Int] ?? []
    }

    func isCompleted(_ kind: SeasonalEventKind, occurrenceYear: Int) -> Bool {
        completedOccurrenceYears(for: kind).contains(occurrenceYear)
    }

    func markCompleted(_ kind: SeasonalEventKind, occurrenceYear: Int) {
        var years = Set(completedOccurrenceYears(for: kind))
        years.insert(occurrenceYear)
        defaults.set(years.sorted(), forKey: holidayKey(kind))
    }

    // MARK: - Daily history

    struct DailyRecord: Codable, Equatable {
        var kind: String
        /// Local calendar day key yyyy-MM-dd (local timezone).
        var dayKey: String
        var timestamp: TimeInterval
    }

    private static let dailyHistoryKey = "warawarapet.seasonal.dailyHistory"

    func dailyHistory() -> [DailyRecord] {
        guard let data = defaults.data(forKey: Self.dailyHistoryKey),
              let records = try? JSONDecoder().decode([DailyRecord].self, from: data) else {
            return []
        }
        return records
    }

    func appendDailyRecord(_ record: DailyRecord) {
        var records = dailyHistory()
        // Keep a bounded window (last 10 records is ample for the
        // cooldown / 24h rules).
        records.append(record)
        if records.count > 10 {
            records.removeFirst(records.count - 10)
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.dailyHistoryKey)
        }
    }

    // MARK: - Daily cooldown stamp

    private static let dailyLastCompletedKey = "warawarapet.seasonal.dailyLastCompleted"

    var lastDailyCompletion: TimeInterval? {
        let value = defaults.double(forKey: Self.dailyLastCompletedKey)
        return value > 0 ? value : nil
    }

    func markDailyCompleted(at timestamp: TimeInterval) {
        defaults.set(timestamp, forKey: Self.dailyLastCompletedKey)
    }
}
