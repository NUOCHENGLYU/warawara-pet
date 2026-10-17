import AppKit
import XCTest
@testable import WarawaraPet

/// Wearable eligibility, precedence, registration and art-integrity
/// coverage for the final gift build.
final class WearableTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WearableTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

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

    func testChristmasWindowStartsDec24At18Local() {
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
        XCTAssertFalse(WearableEligibility.isChristmas(date: date(2026, 12, 24, 17, zone: zone), calendar: cal))
        XCTAssertTrue(WearableEligibility.isChristmas(date: date(2026, 12, 24, 18, zone: zone), calendar: cal))
        XCTAssertTrue(WearableEligibility.isChristmas(date: date(2026, 12, 25, 10, zone: zone), calendar: cal))
        XCTAssertTrue(WearableEligibility.isChristmas(date: date(2026, 12, 26, 23, zone: zone), calendar: cal))
        XCTAssertFalse(WearableEligibility.isChristmas(date: date(2026, 12, 27, 9, zone: zone), calendar: cal))
    }

    func testBirthdayHatOnOctober17Local() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let cal = calendar(zone)
        XCTAssertTrue(WearableEligibility.isBirthday(date: date(2026, 10, 17, 9, zone: zone), calendar: cal))
        XCTAssertFalse(WearableEligibility.isBirthday(date: date(2026, 10, 18, 9, zone: zone), calendar: cal))
    }

    func testLunarNewYearScarfWindow() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let cal = calendar(zone)
        // 2027 CNY = Feb 6: days 1-3 eligible.
        XCTAssertFalse(WearableEligibility.isLunarNewYear(date: date(2027, 2, 5, 12, zone: zone), calendar: cal))
        XCTAssertTrue(WearableEligibility.isLunarNewYear(date: date(2027, 2, 6, 12, zone: zone), calendar: cal))
        XCTAssertTrue(WearableEligibility.isLunarNewYear(date: date(2027, 2, 7, 12, zone: zone), calendar: cal))
        XCTAssertTrue(WearableEligibility.isLunarNewYear(date: date(2027, 2, 8, 12, zone: zone), calendar: cal))
        XCTAssertFalse(WearableEligibility.isLunarNewYear(date: date(2027, 2, 9, 12, zone: zone), calendar: cal))
        // 2025 CNY = Jan 29.
        XCTAssertTrue(WearableEligibility.isLunarNewYear(date: date(2025, 1, 29, 12, zone: zone), calendar: cal))
        XCTAssertFalse(WearableEligibility.isLunarNewYear(date: date(2025, 1, 28, 12, zone: zone), calendar: cal))
    }

    func testHeadwearPrecedenceOrder() {
        XCTAssertGreaterThan(WearableKind.birthdayHat.precedence, WearableKind.christmasHat.precedence)
        XCTAssertGreaterThan(WearableKind.christmasHat.precedence, WearableKind.headphones.precedence)
        XCTAssertFalse(WearableKind.redScarf.isHeadwear)
        XCTAssertTrue(WearableKind.birthdayHat.isHeadwear)
    }

    // MARK: - Registration

    private let renderSize = CGSize(width: 200, height: 226)
    private let bodyBounds = CGRect(x: 0.25, y: 0.18, width: 0.5, height: 0.72)
    private let mouthAnchor = CGPoint(x: 0.5, y: 0.42)

    func testScarfCollarStaysBelowTheMouth() {
        let head = WearableCompositor.headGeometry(
            renderSize: renderSize, bodyBounds: bodyBounds, mouthAnchor: mouthAnchor
        )
        XCTAssertGreaterThan(head.collarY, head.mouthY,
                             "the scarf collar must sit below the mouth")
        // The collar is in the upper body, not a belly belt.
        let bodyTop = bodyBounds.minY * renderSize.height
        let bodyBottom = (bodyBounds.minY + bodyBounds.height) * renderSize.height
        XCTAssertLessThan(head.collarY, bodyTop + (bodyBottom - bodyTop) * 0.55,
                          "the scarf must wrap the upper body, not the belly")
    }

    func testHatBrimContactsTheHeadArc() {
        let head = WearableCompositor.headGeometry(
            renderSize: renderSize, bodyBounds: bodyBounds, mouthAnchor: mouthAnchor
        )
        for box in [WearableCompositor.christmasHatBox, WearableCompositor.birthdayHatBox] {
            let center = WearableCompositor.hatCenter(
                head: head, bodyBounds: bodyBounds, renderSize: renderSize, box: box
            )
            let scale = WearableCompositor.hatScale(
                bodyBounds: bodyBounds, renderSize: renderSize, box: box
            )
            let canvasPt = 1024 * scale
            let brimBottom = center.y + (box.y + box.height - 0.5) * canvasPt
            // The brim bottom sits inside the head (overlap), never
            // floating above it.
            XCTAssertLessThan(brimBottom, head.topCenter.y + head.width * 0.25,
                              "hat brim must contact the head contour")
            XCTAssertGreaterThan(brimBottom, head.topCenter.y - 2,
                                 "hat must not sink deep into the body")
        }
    }

    func testHeadphoneCupLandsAtEarLevel() {
        let head = WearableCompositor.headGeometry(
            renderSize: renderSize, bodyBounds: bodyBounds, mouthAnchor: mouthAnchor
        )
        let center = WearableCompositor.headphonesCenter(
            head: head, bodyBounds: bodyBounds, renderSize: renderSize
        )
        let scale = WearableCompositor.headphonesScale(
            bodyBounds: bodyBounds, renderSize: renderSize
        )
        let canvasPt = 1024 * scale
        let cupCenterFraction = (442.0 + 854.0) / 2 / 1024
        let cupY = center.y + (cupCenterFraction - 0.5) * canvasPt
        XCTAssertEqual(cupY, head.earCenter.y, accuracy: 0.5,
                       "the cup center must sit at the ear level")
        // The near cup is on the visible side; the headset is not tiny.
        XCTAssertGreaterThan(scale * 780, bodyBounds.width * renderSize.width * 0.6,
                             "headphones must span most of the head width")
    }

    func testYawShiftIsSmoothAndBounded() {
        XCTAssertEqual(WearableCompositor.yawShift(yawDegrees: 0, renderSize: renderSize), 0)
        let shift = WearableCompositor.yawShift(yawDegrees: WarawaraTurnGeometry.maxYawDegrees,
                                               renderSize: renderSize)
        XCTAssertLessThan(abs(shift), renderSize.width * 0.1, "yaw shift must stay subtle")
    }

    // MARK: - Art integrity

    func testGiftAssetsMatchDesignLockHashes() {
        let store = GiftAssetStore.shared
        store.reset()
        let verify = store.verifySHA256()
        XCTAssertTrue(verify.ok, verify.details)
        let required = store.verifyAllRequiredAssets()
        XCTAssertTrue(required.ok, required.details)
    }

    func testSplitLayersReconstructTheirSourcesPixelExactly() {
        let store = GiftAssetStore.shared
        store.reset()
        let splits = store.verifySplitIntegrity()
        XCTAssertTrue(splits.ok, splits.details)
    }

    func testBirthdayHatReusesTheInstalledV5Asset() {
        // The final gift reuses the exact accepted Birthday CelFilm v5
        // hat already installed.
        let store = BirthdayAssetStore.shared
        store.reset()
        let v5 = store.optionalImage(named: "birthday_hat.png")
        XCTAssertNotNil(v5, "installed birthday hat must be present")
    }
}
