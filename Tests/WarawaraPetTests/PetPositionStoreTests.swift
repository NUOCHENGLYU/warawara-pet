import XCTest
@testable import WarawaraPet

final class PetPositionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PetPositionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let store = PetPositionStore(defaults: defaults)
        store.saveOrigin(CGPoint(x: 123.5, y: 456.25))
        XCTAssertEqual(store.loadOrigin(), CGPoint(x: 123.5, y: 456.25))
    }

    func testLoadReturnsNilWhenNothingStored() {
        let store = PetPositionStore(defaults: defaults)
        XCTAssertNil(store.loadOrigin())
    }

    func testRestoredFrameReturnsSameOriginWhenInsideScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let origin = CGPoint(x: 200, y: 300)
        let frame = ScreenGeometry.restoredFrame(
            savedOrigin: origin,
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: screens,
            margin: 32
        )
        XCTAssertEqual(frame?.origin, origin)
    }

    func testRestoredFrameClampsPartiallyOffscreenOrigin() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800)]
        let origin = CGPoint(x: 950, y: 750)
        let frame = ScreenGeometry.restoredFrame(
            savedOrigin: origin,
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: screens,
            margin: 32
        )
        XCTAssertNotNil(frame)
        XCTAssertLessThanOrEqual(frame!.maxX, 1000 - 32 + 0.001)
        XCTAssertLessThanOrEqual(frame!.maxY, 800 - 32 + 0.001)
    }

    func testRestoredFrameReturnsNilWhenDisplayIsGone() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let origin = CGPoint(x: 5000, y: 4000)
        let frame = ScreenGeometry.restoredFrame(
            savedOrigin: origin,
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: screens,
            margin: 32
        )
        XCTAssertNil(frame)
    }

    func testRestoredFrameUsesSecondaryDisplay() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        ]
        let origin = CGPoint(x: 2100, y: 300)
        let frame = ScreenGeometry.restoredFrame(
            savedOrigin: origin,
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: screens,
            margin: 32
        )
        XCTAssertEqual(frame?.origin, origin)
    }

    func testRestoredPositionFrameUsesSavedOriginWhenValid() {
        let saved = CGPoint(x: 200, y: 300)
        let frame = ScreenGeometry.restoredPositionFrame(
            savedOrigin: saved,
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)],
            restoreMargin: 32,
            defaultVisibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        XCTAssertEqual(frame.origin, saved)
    }

    func testRestoredPositionFrameFallsBackToDefaultWhenNothingSaved() {
        let defaultVisible = CGRect(x: 0, y: 60, width: 1920, height: 1020)
        let frame = ScreenGeometry.restoredPositionFrame(
            savedOrigin: nil,
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)],
            restoreMargin: 32,
            defaultVisibleFrame: defaultVisible
        )
        XCTAssertEqual(
            frame,
            FrameMath.initialFrame(petSize: CGSize(width: 160, height: 160), in: defaultVisible)
        )
    }

    func testRestoredPositionFrameFallsBackToDefaultWhenDisplayGone() {
        let defaultVisible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = ScreenGeometry.restoredPositionFrame(
            savedOrigin: CGPoint(x: 5000, y: 4000),
            petSize: CGSize(width: 160, height: 160),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)],
            restoreMargin: 32,
            defaultVisibleFrame: defaultVisible
        )
        XCTAssertEqual(
            frame,
            FrameMath.initialFrame(petSize: CGSize(width: 160, height: 160), in: defaultVisible)
        )
    }
}
