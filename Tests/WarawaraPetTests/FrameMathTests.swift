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
