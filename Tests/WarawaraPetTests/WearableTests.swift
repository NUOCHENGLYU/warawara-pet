import AppKit
import XCTest
@testable import WarawaraPet

/// Birthday-hat-only wearable coverage for the final gift build:
/// calendar eligibility, hat registration, and art integrity.
final class WearableTests: XCTestCase {
    private func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int,
                      zone: TimeZone, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.timeZone = zone
        return calendar(zone).date(from: components)!
    }

    // MARK: - Eligibility

    func testBirthdayHatOnOctober17Local() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let cal = calendar(zone)
        XCTAssertTrue(BirthdayDateMath.isBirthday(date: date(2026, 10, 17, 9, zone: zone), calendar: cal))
        XCTAssertFalse(BirthdayDateMath.isBirthday(date: date(2026, 10, 18, 9, zone: zone), calendar: cal))
    }

    // MARK: - Registration

    private let renderSize = CGSize(width: 200, height: 226)
    private let bodyBounds = CGRect(x: 0.25, y: 0.18, width: 0.5, height: 0.72)

    func testHatBrimContactsTheHeadArc() {
        let head = WearableCompositor.headGeometry(
            renderSize: renderSize, bodyBounds: bodyBounds
        )
        let box = WearableCompositor.birthdayHatBox
        let center = WearableCompositor.hatCenter(
            head: head, bodyBounds: bodyBounds, renderSize: renderSize, box: box
        )
        let scale = WearableCompositor.hatScale(
            bodyBounds: bodyBounds, renderSize: renderSize, box: box
        )
        let canvasPt = 1024 * scale
        let brimBottom = center.y + (box.y + box.height - 0.5) * canvasPt
        // The brim bottom sits inside the head (overlap), never floating
        // above it and never sinking deep into the body.
        XCTAssertLessThan(brimBottom, head.topCenter.y + head.width * 0.25,
                          "hat brim must contact the head contour")
        XCTAssertGreaterThan(brimBottom, head.topCenter.y - 2,
                             "hat must not sink deep into the body")
        // The hat is not tiny relative to the head.
        XCTAssertGreaterThan(scale * box.width * 1024, bodyBounds.width * renderSize.width * 0.4,
                             "hat must be a natural head size")
    }

    // MARK: - Art integrity

    func testGiftAssetsMatchDesignLockHashes() {
        let store = GiftAssetStore.shared
        store.reset()
        let verify = store.verifySHA256()
        XCTAssertTrue(verify.ok, verify.details)
        let required = store.verifyAllRequiredAssets()
        XCTAssertTrue(required.ok, required.details)
        XCTAssertNotNil(store.image(named: "meteor_celfilm.png"))
    }

    func testBirthdayHatReusesTheInstalledV5Asset() {
        // The final gift reuses the exact accepted Birthday CelFilm v5
        // hat already installed (design lock).
        let store = BirthdayAssetStore.shared
        store.reset()
        XCTAssertNotNil(store.optionalImage(named: "birthday_hat.png"),
                        "installed birthday hat must be present")
    }

    // MARK: - Controller

    func testControllerWearsTheHatOnOctober17AndOnCelebrationRequest() {
        final class FixedClock: BirthdayClock {
            var currentNow: Date
            let calendar: Calendar
            init(now: Date, calendar: Calendar) { self.currentNow = now; self.calendar = calendar }
            func now() -> Date { currentNow }
        }
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
        let runtime = WearableRuntime()
        let controller = WearableController(
            runtime: runtime,
            clock: FixedClock(now: date(2026, 10, 17, 10, zone: zone), calendar: cal)
        )
        for _ in 0..<24 { controller.tick() } // ~6s of easing
        XCTAssertTrue(runtime.state.birthdayHat, "October 17 wears the hat")

        // Off-date with a celebration request: the hat appears.
        let offDate = FixedClock(now: date(2026, 11, 5, 10, zone: zone), calendar: cal)
        let runtime2 = WearableRuntime()
        let controller2 = WearableController(runtime: runtime2, clock: offDate)
        controller2.celebrationRequestsBirthdayHat = true
        for _ in 0..<24 { controller2.tick() }
        XCTAssertTrue(runtime2.state.birthdayHat, "first-launch celebration wears the hat")

        // Request withdrawn: the hat crossfades away.
        controller2.celebrationRequestsBirthdayHat = false
        for _ in 0..<48 { controller2.tick() }
        XCTAssertFalse(runtime2.state.birthdayHat, "hat removed after the celebration")
    }
}
