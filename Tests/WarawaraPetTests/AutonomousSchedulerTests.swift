import XCTest
@testable import WarawaraPet

final class AutonomousSchedulerTests: XCTestCase {
    func testNextDelayStaysWithinHopBounds() {
        var rng = SeededRandomSource(seed: 7)
        let tuning = PersonalityTuning.default
        for _ in 0..<200 {
            let delay = AutonomousScheduler.nextDelay(using: &rng, tuning: tuning)
            XCTAssertTrue((tuning.hopMinDelay...tuning.hopMaxDelay).contains(delay))
        }
    }

    func testFloatRequiresEligibility() {
        var alwaysFloat = PersonalityTuning.default
        alwaysFloat.floatChance = 1
        var rng = SeededRandomSource(seed: 1)
        XCTAssertEqual(
            AutonomousScheduler.nextAction(now: 50, floatEligibleSince: 75, using: &rng, tuning: alwaysFloat),
            .hop
        )
        XCTAssertEqual(
            AutonomousScheduler.nextAction(now: 75, floatEligibleSince: 75, using: &rng, tuning: alwaysFloat),
            .float
        )
    }

    func testZeroFloatChanceAlwaysHops() {
        var noFloat = PersonalityTuning.default
        noFloat.floatChance = 0
        var rng = SeededRandomSource(seed: 2)
        for _ in 0..<200 {
            XCTAssertEqual(
                AutonomousScheduler.nextAction(now: 1000, floatEligibleSince: 0, using: &rng, tuning: noFloat),
                .hop
            )
        }
    }

    func testEligibleFloatFrequencyIsRareButPresent() {
        let tuning = PersonalityTuning.default  // floatChance 0.2
        var rng = SeededRandomSource(seed: 42)
        var floats = 0
        for _ in 0..<2000 {
            if AutonomousScheduler.nextAction(now: 100, floatEligibleSince: 0, using: &rng, tuning: tuning) == .float {
                floats += 1
            }
        }
        XCTAssertTrue((330...470).contains(floats), "unexpected float frequency: \(floats)")
    }

    func testSchedulerIsDeterministicForSameSeed() {
        var a = SeededRandomSource(seed: 123)
        var b = SeededRandomSource(seed: 123)
        let tuning = PersonalityTuning.default
        for _ in 0..<50 {
            XCTAssertEqual(
                AutonomousScheduler.nextAction(now: 100, floatEligibleSince: 0, using: &a, tuning: tuning),
                AutonomousScheduler.nextAction(now: 100, floatEligibleSince: 0, using: &b, tuning: tuning)
            )
            XCTAssertEqual(
                AutonomousScheduler.nextDelay(using: &a, tuning: tuning),
                AutonomousScheduler.nextDelay(using: &b, tuning: tuning)
            )
        }
    }
}
