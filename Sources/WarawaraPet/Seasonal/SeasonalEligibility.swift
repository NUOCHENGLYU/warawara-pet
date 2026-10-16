import Foundation

/// Pure local-calendar eligibility for the three holiday events.
/// The recipient Mac's current calendar/timezone drives everything —
/// never UTC, never hardcoded Gregorian dates.
enum SeasonalEligibility {
    /// Chinese New Year: lunar first month, days 1–3. Uses
    /// Calendar(identifier: .chinese) with the local timezone.
    /// For testing: 2027 CNY starts Feb 6, 2027 (Gregorian).
    /// Note: a LEAP lunar first month cannot be distinguished without
    /// the macOS 14 `isLeapMonth` API (deployment target is macOS 13);
    /// the next leap first month occurs in 2262, so month == 1 is
    /// unambiguous for any realistic date range.
    static func isChineseNewYear(
        date: Date,
        calendar: Calendar
    ) -> Bool {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        let components = chinese.dateComponents([.month, .day], from: date)
        guard let day = components.day else { return false }
        return components.month == 1 && (1...3).contains(day)
    }

    /// Christmas: December 24 from 18:00 local through December 26.
    static func isChristmas(date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.month, .day, .hour], from: date)
        guard let month = components.month, let day = components.day else { return false }
        if month == 12, day == 24 {
            return (components.hour ?? 0) >= 18
        }
        return month == 12 && (day == 25 || day == 26)
    }

    /// Gregorian New Year: January 1, local.
    static func isNewYear(date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.month, .day], from: date)
        return components.month == 1 && components.day == 1
    }

    /// Holiday eligibility for a kind.
    static func isEligible(_ kind: SeasonalEventKind, date: Date, calendar: Calendar) -> Bool {
        switch kind {
        case .cny: return isChineseNewYear(date: date, calendar: calendar)
        case .christmas: return isChristmas(date: date, calendar: calendar)
        case .newYear: return isNewYear(date: date, calendar: calendar)
        case .umbrella, .hotCocoa, .sprout, .paperAirplane: return false
        }
    }

    /// The "occurrence year" for annual persistence: the local Gregorian
    /// year containing the eligible day (works for CNY 2027 = 2027 and
    /// for Dec 24–26 / Jan 1 trivially).
    static func occurrenceYear(for kind: SeasonalEventKind, date: Date, calendar: Calendar) -> Int {
        calendar.component(.year, from: date)
    }
}
