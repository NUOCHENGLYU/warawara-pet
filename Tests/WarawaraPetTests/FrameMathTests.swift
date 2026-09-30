import XCTest
@testable import WarawaraPet

final class FrameMathTests: XCTestCase {
    func testPlacesPetAtBottomRightWithDefaultMarginOnLargeScreen() {
        let screen = CGRect(x: 0, y: 60, width: 1920, height: 1020)
        let frame = FrameMath.initialFrame(
            petSize: CGSize(width: 160, height: 160),
            in: screen
        )

        XCTAssertEqual(frame.size, CGSize(width: 160, height: 160))
        XCTAssertEqual(frame.maxX, screen.maxX - 32, accuracy: 0.001)
        XCTAssertEqual(frame.minY, screen.minY + 32, accuracy: 0.001)
    }

    func testRespectsCustomMargin() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = FrameMath.initialFrame(
            petSize: CGSize(width: 160, height: 160),
            in: screen,
            margin: 60
        )

        XCTAssertEqual(frame.maxX, screen.maxX - 60, accuracy: 0.001)
        XCTAssertEqual(frame.minY, screen.minY + 60, accuracy: 0.001)
    }

    func testClampsSizeAndOriginWhenScreenIsSmallerThanPet() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 80)
        let frame = FrameMath.initialFrame(
            petSize: CGSize(width: 160, height: 160),
            in: screen
        )

        XCTAssertEqual(frame.size, CGSize(width: 100, height: 80))
        XCTAssertEqual(frame.origin, CGPoint(x: 0, y: 0))
    }

    func testStaysInsideVisibleFrameWithNonZeroOrigin() {
        let screen = CGRect(x: -600, y: 80, width: 1200, height: 700)
        let frame = FrameMath.initialFrame(
            petSize: CGSize(width: 160, height: 160),
            in: screen
        )

        XCTAssertTrue(screen.contains(frame))
    }
}

final class ScreenGeometryTests: XCTestCase {
    func testClampFrameKeepsInsideFrameUnchanged() {
        let visible = CGRect(x: 0, y: 60, width: 1920, height: 1020)
        let frame = CGRect(x: 100, y: 200, width: 160, height: 160)
        XCTAssertEqual(
            ScreenGeometry.clampFrame(frame, to: visible, margin: 8),
            frame
        )
    }

    func testClampFramePullsOverflowingFrameBackWithMargin() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = CGRect(x: 990, y: 780, width: 160, height: 160)
        let clamped = ScreenGeometry.clampFrame(frame, to: visible, margin: 8)
        XCTAssertEqual(clamped.maxX, 1000 - 8, accuracy: 0.001)
        XCTAssertEqual(clamped.maxY, 800 - 8, accuracy: 0.001)
    }

    func testClampFrameClampsNegativeOrigins() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = CGRect(x: -100, y: -50, width: 160, height: 160)
        let clamped = ScreenGeometry.clampFrame(frame, to: visible, margin: 8)
        XCTAssertEqual(clamped.origin, CGPoint(x: 8, y: 8))
    }

    func testClampFrameWithZeroMargin() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 400)
        let frame = CGRect(x: 480, y: 380, width: 160, height: 160)
        let clamped = ScreenGeometry.clampFrame(frame, to: visible, margin: 0)
        XCTAssertEqual(clamped.maxX, 500, accuracy: 0.001)
        XCTAssertEqual(clamped.maxY, 400, accuracy: 0.001)
    }

    func testClampFrameShrinksOversizedFrameToVisibleBounds() {
        let visible = CGRect(x: 0, y: 0, width: 100, height: 80)
        let frame = CGRect(x: -20, y: -10, width: 160, height: 160)
        let clamped = ScreenGeometry.clampFrame(frame, to: visible, margin: 0)
        XCTAssertEqual(clamped.size, CGSize(width: 100, height: 80))
    }

    func testVisibleFrameContainingPointPicksMatchingScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1000, height: 800)
        ]
        XCTAssertEqual(
            ScreenGeometry.visibleFrame(containing: CGPoint(x: 1200, y: 100), candidates: screens),
            screens[1]
        )
        XCTAssertNil(
            ScreenGeometry.visibleFrame(containing: CGPoint(x: 3000, y: 100), candidates: screens)
        )
    }
}
