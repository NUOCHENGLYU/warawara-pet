import XCTest
@testable import WarawaraPet

final class RandomSourceTests: XCTestCase {
    func testSeededSourceIsDeterministic() {
        var a = SeededRandomSource(seed: 7)
        var b = SeededRandomSource(seed: 7)
        for _ in 0..<50 {
            XCTAssertEqual(a.nextUnit(), b.nextUnit())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededRandomSource(seed: 1)
        var b = SeededRandomSource(seed: 2)
        var different = false
        for _ in 0..<50 where a.nextUnit() != b.nextUnit() {
            different = true
            break
        }
        XCTAssertTrue(different)
    }

    func testSeededOutputStaysInUnitRange() {
        var rng = SeededRandomSource(seed: 99)
        for _ in 0..<500 {
            let value = rng.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testSystemSourceStaysInUnitRange() {
        var rng = SystemRandomSource()
        for _ in 0..<200 {
            let value = rng.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testRandomDelayRespectsBounds() {
        var rng = SeededRandomSource(seed: 3)
        for _ in 0..<200 {
            let delay = RandomBounds.randomDelay(in: 6...14, using: &rng)
            XCTAssertTrue((6...14).contains(delay))
        }
    }

    func testRandomCGFloatRespectsBounds() {
        var rng = SeededRandomSource(seed: 5)
        for _ in 0..<200 {
            let value = RandomBounds.randomCGFloat(in: -40...40, using: &rng)
            XCTAssertTrue((-40...40).contains(value))
        }
    }

    func testRandomDelayHandlesInvertedRange() {
        var rng = SeededRandomSource(seed: 11)
        for _ in 0..<200 {
            let delay = RandomBounds.randomDelay(in: 14...6, using: &rng)
            XCTAssertTrue((6...14).contains(delay))
        }
    }
}
