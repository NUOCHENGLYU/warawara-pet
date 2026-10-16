import Foundation

/// Injectable local calendar/clock so birthday eligibility is
/// deterministic in tests. The production implementation uses the
/// RECIPIENT MAC's local calendar and timezone — never a fixed offset.
protocol BirthdayClock {
    func now() -> Date
    var calendar: Calendar { get }
}

struct SystemBirthdayClock: BirthdayClock {
    func now() -> Date { Date() }
    var calendar: Calendar { Calendar.autoupdatingCurrent }
}

/// Pure birthday date math. The birthday is October 17 in whatever
/// calendar/timezone the system reports locally.
enum BirthdayDateMath {
    static let birthdayMonth = 10
    static let birthdayDay = 17

    static func isBirthday(_ components: DateComponents) -> Bool {
        components.month == birthdayMonth && components.day == birthdayDay
    }

    static func isBirthday(date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.month, .day, .year], from: date)
        return isBirthday(components)
    }
}

/// UserDefaults persistence for the birthday event:
/// - annual completion records (once per local calendar year)
/// - envelope unlock (once unlocked, the envelope stays available on
///   every launch so the letter can be reopened at any time)
struct BirthdayPersistence {
    static let completedYearsKey = "warawarapet.birthday.completedYears"
    static let envelopeUnlockedKey = "warawarapet.birthday.envelopeUnlocked"
    static let envelopeRetiredKey = "warawarapet.birthday.envelopeRetired"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func completedYears() -> [Int] {
        defaults.array(forKey: Self.completedYearsKey) as? [Int] ?? []
    }

    func isCompleted(year: Int) -> Bool {
        completedYears().contains(year)
    }

    func markCompleted(year: Int) {
        var years = Set(completedYears())
        years.insert(year)
        defaults.set(years.sorted(), forKey: Self.completedYearsKey)
    }

    func markEnvelopeUnlocked() {
        defaults.set(true, forKey: Self.envelopeUnlockedKey)
    }

    var envelopeUnlocked: Bool {
        defaults.bool(forKey: Self.envelopeUnlockedKey)
    }

    /// The large desktop envelope was retired after the first read;
    /// letter access continues via pet double-click.
    func markEnvelopeRetired() {
        defaults.set(true, forKey: Self.envelopeRetiredKey)
    }

    var envelopeRetired: Bool {
        defaults.bool(forKey: Self.envelopeRetiredKey)
    }

    /// The letter remains available whenever the envelope was ever
    /// unlocked — retirement only changes HOW it is presented.
    var isLetterAvailable: Bool {
        envelopeUnlocked
    }
}
