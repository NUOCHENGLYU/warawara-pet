import XCTest
@testable import WarawaraPet

final class CuriosityDetectorTests: XCTestCase {
    private var tuning: PersonalityTuning {
        var t = PersonalityTuning.default
        t.curiosityEnterRadius = 110
        t.curiosityExitRadius = 170
        t.curiosityDwellTime = 1.2
        return t
    }

    func testEngagesAfterDwellTimeInsideRadius() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<10 {
            t += 0.15
            detector.update(distance: 60, at: t)
        }
        XCTAssertEqual(detector.phase, .engaged)
        XCTAssertEqual(detector.dwellProgress, 1, accuracy: 0.0001)
    }

    func testShortInsideVisitStaysWatching() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<4 {
            t += 0.15
            detector.update(distance: 60, at: t)
        }
        XCTAssertEqual(detector.phase, .watching)
        XCTAssertLessThan(detector.dwellProgress, 1)
    }

    func testDwellResetsWhenPointerLeaves() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<6 {
            t += 0.15
            detector.update(distance: 60, at: t)   // 0.9 s inside
        }
        t += 0.15
        detector.update(distance: 500, at: t)      // leave
        XCTAssertEqual(detector.phase, .away)
        XCTAssertEqual(detector.dwellProgress, 0)
        for _ in 0..<6 {
            t += 0.15
            detector.update(distance: 60, at: t)   // 0.9 s inside again
        }
        XCTAssertEqual(detector.phase, .watching)  // never reached 1.2 contiguous
    }

    func testOscillationAtEnterRadiusNeverEngages() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<30 {
            t += 0.15
            detector.update(distance: 105, at: t)  // just inside
            t += 0.15
            detector.update(distance: 115, at: t)  // just outside: resets dwell
        }
        XCTAssertNotEqual(detector.phase, .engaged)
    }

    func testHysteresisBandKeepsEngaged() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<10 {
            t += 0.15
            detector.update(distance: 60, at: t)
        }
        XCTAssertEqual(detector.phase, .engaged)

        // Inside the band between enter (110) and exit (170): stays engaged.
        for _ in 0..<20 {
            t += 0.15
            detector.update(distance: 140, at: t)
        }
        XCTAssertEqual(detector.phase, .engaged)
    }

    func testExitsOnlyBeyondExitRadius() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<10 {
            t += 0.15
            detector.update(distance: 60, at: t)
        }
        XCTAssertEqual(detector.phase, .engaged)

        t += 0.15
        detector.update(distance: 200, at: t)
        XCTAssertEqual(detector.phase, .away)
    }

    func testDwellProgressIsMonotonicWhileWatching() {
        var detector = CuriosityDetector(tuning: tuning)
        var t: TimeInterval = 0
        var previous: CGFloat = 0
        for _ in 0..<10 {
            t += 0.15
            detector.update(distance: 60, at: t)
            if detector.phase == .watching {
                XCTAssertGreaterThanOrEqual(detector.dwellProgress, previous)
                previous = detector.dwellProgress
            }
        }
        XCTAssertEqual(detector.phase, .engaged)
    }
}
