import AppKit
import Foundation

/// The 12 seasonal & daily CelFilm v1 props. Stable IDs, extensible
/// definitions — future events add cases + a definition entry only.
enum SeasonalEventKind: String, CaseIterable, Equatable {
    case cny
    case christmas
    case newYear
    case umbrella
    case hotCocoa
    case sprout
    case paperAirplane

    /// Manual replay argument value.
    var replayArgument: String {
        switch self {
        case .cny: return "cny"
        case .christmas: return "christmas"
        case .newYear: return "newyear"
        case .umbrella: return "umbrella"
        case .hotCocoa: return "hot-cocoa"
        case .sprout: return "sprout"
        case .paperAirplane: return "paper-airplane"
        }
    }

    static func fromReplayArgument(_ argument: String) -> SeasonalEventKind? {
        allCases.first { $0.replayArgument == argument }
    }

    /// Holiday kinds (annual completions) vs daily micro-events.
    var isHoliday: Bool {
        switch self {
        case .cny, .christmas, .newYear: return true
        case .umbrella, .hotCocoa, .sprout, .paperAirplane: return false
        }
    }

    /// Priority rank (lower = higher priority). Birthday is rank 0 and
    /// lives outside this enum by design.
    var priorityRank: Int {
        switch self {
        case .cny: return 1
        case .christmas: return 2
        case .newYear: return 3
        case .umbrella, .hotCocoa, .sprout, .paperAirplane: return 4
        }
    }

    /// Scene duration range (seconds) per the story spec.
    var durationRange: ClosedRange<TimeInterval> {
        switch self {
        case .cny: return 25...40
        case .christmas: return 25...40
        case .newYear: return 20...30
        case .umbrella: return 12...18
        case .hotCocoa: return 12...18
        case .sprout: return 10...16
        case .paperAirplane: return 8...15
        }
    }

    /// Primary + secondary prop assets for the scene.
    var primaryAsset: String {
        switch self {
        case .cny: return "cny_hongbao.png"
        case .christmas: return "xmas_gift.png"
        case .newYear: return "newyear_calendar_jan1.png"
        case .umbrella: return "daily_umbrella.png"
        case .hotCocoa: return "daily_hot_cocoa.png"
        case .sprout: return "daily_sprout.png"
        case .paperAirplane: return "daily_paper_airplane.png"
        }
    }

    var secondaryAssets: [String] {
        switch self {
        case .cny: return ["cny_lantern.png", "cny_plum_branch.png"]
        case .christmas: return ["xmas_wreath.png"]
        case .newYear: return ["newyear_party_popper.png"]
        case .umbrella, .hotCocoa, .sprout, .paperAirplane: return []
        }
    }

    /// Decorative-only assets (shown briefly, never interactive).
    var decorativeAssets: [String] {
        switch self {
        case .cny: return ["cny_firecracker_hanging.png"]
        default: return []
        }
    }

    /// Every production PNG the runtime scene must load and draw
    /// (primary + secondaries + decorative). The presenter verifies all
    /// of these at scene start.
    var displayedAssets: [String] {
        [primaryAsset] + secondaryAssets + decorativeAssets
    }

    /// Whether the scene carries secondary/decorative props in addition
    /// to the primary one (CNY lanterns/plum, Christmas wreath, New Year
    /// popper, CNY firecrackers).
    var showsSecondaryDecor: Bool {
        !secondaryAssets.isEmpty || !decorativeAssets.isEmpty
    }
}

/// Typed loader for the seasonal/daily props. Same candidate strategy
/// as the birthday store (dev + packaged app); graceful fallback.
final class SeasonalAssetStore {
    static let shared = SeasonalAssetStore()

    /// The 12 required PNGs (decorative firecrackers included — they are
    /// scene props, never interactive).
    static let requiredFileNames: [String] = [
        "cny_lantern.png", "cny_hongbao.png", "cny_plum_branch.png",
        "cny_firecracker_hanging.png", "xmas_wreath.png", "xmas_gift.png",
        "newyear_calendar_jan1.png", "newyear_party_popper.png",
        "daily_umbrella.png", "daily_hot_cocoa.png", "daily_sprout.png",
        "daily_paper_airplane.png"
    ]

    /// SHA256 from ASSET_MANIFEST.json (verification only).
    static let expectedSHA256: [String: String] = [
        "cny_lantern.png": "d4b78043499594c008ff334f62e5f624ab18749927eb435a6f7d17a3a24ed1aa",
        "cny_hongbao.png": "dbaa917c2fd37f9725a6983d96b2653e65a26a62dbcc73e67306c3433cea1cf9",
        "cny_plum_branch.png": "a5c884ae79a75b2644d2e87842a1928bc3b6e751a62a07698b091ee0665bc5aa",
        "cny_firecracker_hanging.png": "cd1d0aa76f4a100ec30c9a8b2d7a53eedfb6df63ff0dcffd1fcf6e23ad0b7c06",
        "xmas_wreath.png": "2335bf4387e2303609f29fb67c0d458323c8c7daf793cf4f8f29dfe3e74922fe",
        "xmas_gift.png": "1fa394127fefc6abe2dca44b4f60c466a82e166790b965cf6ee70f588c7f76c8",
        "newyear_calendar_jan1.png": "7e2e3f87c4a0088a3b9da32e423d25eb4653730f0dd7f5830ce623360ee1071e",
        "newyear_party_popper.png": "5c512c58ef2e570666476a99d67ad0ab37403e11d61c4dbac06043e52e122382",
        "daily_umbrella.png": "bf53b2aeb8e1e6c3aea6e6df2b80023a33277625506a0f474e1f97a92b201160",
        "daily_hot_cocoa.png": "ee1a10728cad661b6c0c9c159f28cff430f3fb64f32873e7c59f1ffb0c51e036",
        "daily_sprout.png": "09be867a03324115eed693f2969733594ba9633d1a73200a0878fb74bbb6cc3b",
        "daily_paper_airplane.png": "2c64f562853a6fbf4019ca5d4b8301722f74e8f9a3b303acc3b0df031958268d"
    ]

    /// CelFilm v3 ADDITIVE optional assets (verified against their own
    /// manifest). Absence must never break a scene — the choreography
    /// falls back to the v1 artwork.
    static let optionalFileNames: [String] = [
        "cny_hongbao_open.png", "cny_hongbao_note.png",
        "xmas_gift_open_base.png", "xmas_gift_lid.png", "xmas_gift_open.png",
        "daily_umbrella_closed.png", "rain_drops_overlay.png",
        "paper_airplane_trail.png", "newyear_confetti_overlay.png"
    ]

    static let optionalSHA256: [String: String] = [
        "cny_hongbao_open.png": "031ba34397cc4683b8ef42d059269236ea58bb4ba5a2b59b6c26e464db048d27",
        "cny_hongbao_note.png": "7cf18266f0eeedbaf151ed56502db5363cf01e40d4e7f9c01df08f33563a61b7",
        "xmas_gift_open_base.png": "4ebe5ac84a0cf8b0878fe402d2c452b175278ddf181fe98c5f31e626bd3a7440",
        "xmas_gift_lid.png": "0cb55a660f5bf821acb23e7c8e5fe41969f8979c2ddb6475c286a6301f084cee",
        "xmas_gift_open.png": "9d02302269ac774f8e10ff57a12023ee04d74387eed18d551e0d8f4b1c07369a",
        "daily_umbrella_closed.png": "49297a10653257087dbcbd6728e408853a31acfd99f233c8139343bf784e8370",
        "rain_drops_overlay.png": "59f14b1c92591742394f60ad7cd250f3e4883da5aed3ee7c1f631728dc9082d2",
        "paper_airplane_trail.png": "7a162525d05c3a378082f3faae10d935e7a6f1279d4788a28a4626cdd49af7f7",
        "newyear_confetti_overlay.png": "6f985d378a5b546233a36e7e0dfa5f51ad80f3cf3130520ab33f39ed3841e603"
    ]

    private var imageCache: [String: NSImage] = [:]
    private var resolvedBaseURL: URL?

    static func candidateBaseURLs() -> [URL] {
        var roots: [URL] = []
        #if SWIFT_PACKAGE
        if let url = Bundle.module.resourceURL { roots.append(url) }
        #endif
        if let url = Bundle.main.resourceURL { roots.append(url) }
        roots.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        )
        roots.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/WarawaraPet/Resources")
        )
        return roots.map { $0.appendingPathComponent("Seasonal") }
    }

    func resolveBaseURL() -> URL? {
        if let resolvedBaseURL { return resolvedBaseURL }
        for candidate in Self.candidateBaseURLs()
        where FileManager.default.fileExists(atPath: candidate.path) {
            resolvedBaseURL = candidate
            return candidate
        }
        return nil
    }

    func image(named fileName: String) -> NSImage? {
        if let cached = imageCache[fileName] { return cached }
        guard let base = resolveBaseURL() else { return nil }
        let url = base.appendingPathComponent(fileName)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[fileName] = image
        return image
    }

    /// Optional CelFilm v3 layer lookup: nil when absent or undecodable —
    /// scenes degrade to the v1 artwork gracefully.
    func optionalImage(named fileName: String) -> NSImage? {
        image(named: fileName)
    }

    /// True when every v3 optional asset resolves and decodes.
    func optionalAssetsPresent() -> (present: Int, total: Int) {
        var present = 0
        for name in Self.optionalFileNames {
            if image(named: name) != nil { present += 1 }
        }
        return (present, Self.optionalFileNames.count)
    }

    /// Verification-only check of the optional assets (absent files are
    /// reported, not failed).
    func verifyOptionalAssets() -> (ok: Bool, details: String) {
        var mismatches: [String] = []
        var missing: [String] = []
        for (name, expected) in Self.optionalSHA256 {
            guard let base = resolveBaseURL(),
                  let data = try? Data(contentsOf: base.appendingPathComponent(name)) else {
                missing.append(name)
                continue
            }
            if BirthdaySHA256.hash(data) != expected {
                mismatches.append(name)
            }
        }
        if mismatches.isEmpty && missing.isEmpty {
            return (true, "all \(Self.optionalSHA256.count) optional assets match")
        }
        return (false, "mismatched: \(mismatches) missing: \(missing)")
    }

    func verifyAllRequiredAssets() -> (ok: Bool, details: String) {
        var missing: [String] = []
        var undecodable: [String] = []
        for name in Self.requiredFileNames {
            guard resolveBaseURL() != nil,
                  FileManager.default.fileExists(
                    atPath: (resolveBaseURL() ?? URL(fileURLWithPath: "/")).appendingPathComponent(name).path
                  ) else {
                missing.append(name)
                continue
            }
            if image(named: name) == nil { undecodable.append(name) }
        }
        if missing.isEmpty && undecodable.isEmpty {
            return (true, "all \(Self.requiredFileNames.count) assets present")
        }
        return (false, "missing: \(missing) undecodable: \(undecodable)")
    }

    func verifySHA256() -> (ok: Bool, details: String) {
        var mismatches: [String] = []
        var missing: [String] = []
        for (name, expected) in Self.expectedSHA256 {
            guard let base = resolveBaseURL() else {
                missing.append(name)
                continue
            }
            guard let data = try? Data(contentsOf: base.appendingPathComponent(name)) else {
                missing.append(name)
                continue
            }
            if BirthdaySHA256.hash(data) != expected {
                mismatches.append(name)
            }
        }
        if mismatches.isEmpty && missing.isEmpty {
            return (true, "all \(Self.expectedSHA256.count) hashes match")
        }
        return (false, "mismatched: \(mismatches) missing: \(missing)")
    }

    func reset() {
        imageCache.removeAll()
        resolvedBaseURL = nil
    }
}
