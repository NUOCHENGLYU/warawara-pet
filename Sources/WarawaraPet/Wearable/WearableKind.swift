import Foundation

/// Wearables in the final gift build. Design-locked artwork only:
/// the Christmas hat, the navy/cream headphones, and the red knitted
/// scarf with its original pattern and tassels.
enum WearableKind: String, CaseIterable, Equatable {
    case birthdayHat
    case christmasHat
    case headphones
    case redScarf

    /// Headwear precedence: the birthday hat wins on October 17 and
    /// during celebrations, the Christmas hat during Christmas, and the
    /// headphones whenever audio playback is detected.
    var precedence: Int {
        switch self {
        case .birthdayHat: return 3
        case .christmasHat: return 2
        case .headphones: return 1
        case .redScarf: return 0
        }
    }

    var isHeadwear: Bool { self != .redScarf }

    var displayName: String {
        switch self {
        case .birthdayHat: return "birthday hat"
        case .christmasHat: return "christmas hat"
        case .headphones: return "headphones"
        case .redScarf: return "red scarf"
        }
    }

    init?(debugArgument: String) {
        switch debugArgument {
        case "birthday-hat": self = .birthdayHat
        case "christmas-hat": self = .christmasHat
        case "headphones": self = .headphones
        case "red-scarf": self = .redScarf
        default: return nil
        }
    }
}

/// Pure calendar eligibility for the calendar-driven wearables.
enum WearableEligibility {
    /// Christmas hat: December 24 at 18:00 local through December 26
    /// inclusive.
    static func isChristmas(date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = components.year,
              let start = calendar.date(from: DateComponents(year: year, month: 12, day: 24, hour: 18)),
              let end = calendar.date(from: DateComponents(year: year, month: 12, day: 26, hour: 23, minute: 59)) else {
            return false
        }
        return date >= start && date <= end
    }

    /// Birthday hat: October 17 in the local calendar.
    static func isBirthday(date: Date, calendar: Calendar) -> Bool {
        BirthdayDateMath.isBirthday(date: date, calendar: calendar)
    }

    /// Red scarf: Lunar New Year day 1 through day 3 (local calendar).
    static func isLunarNewYear(date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return false }
        guard let cnyStart = LunarNewYearCalculator.cnyStartDate(
            gregorianYear: year, calendar: calendar
        ) else { return false }
        let day1 = calendar.dateComponents([.month, .day], from: cnyStart)
        // Days 1-3 of the lunar year (local Gregorian mapping).
        guard let day1Date = calendar.date(from: DateComponents(
            year: year, month: day1.month, day: day1.day
        )) else { return false }
        for offset in 0..<3 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: day1Date) else { continue }
            let c = calendar.dateComponents([.month, .day], from: candidate)
            if c.month == month && c.day == day { return true }
        }
        return false
    }
}

/// Deterministic Lunar New Year (CNY day 1) lookup for a Gregorian
/// year, using authoritative astronomical dates. Pure and unit-tested
/// against the known anchors (2027-02-06, 2026-02-17, 2025-01-29,
/// 2028-01-26). Covers 2024-2035 — enough for the gift's lifetime.
enum LunarNewYearCalculator {
    static func cnyStartDate(gregorianYear: Int, calendar: Calendar) -> Date? {
        let known: [Int: (Int, Int)] = [
            2024: (2, 10),
            2025: (1, 29),
            2026: (2, 17),
            2027: (2, 6),
            2028: (1, 26),
            2029: (2, 13),
            2030: (2, 3),
            2031: (1, 23),
            2032: (2, 11),
            2033: (1, 31),
            2034: (2, 19),
            2035: (2, 8)
        ]
        guard let anchor = known[gregorianYear] else { return nil }
        return calendar.date(from: DateComponents(
            year: gregorianYear, month: anchor.0, day: anchor.1
        ))
    }
}
