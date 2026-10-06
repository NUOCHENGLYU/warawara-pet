import XCTest
@testable import WarawaraPet

final class AutonomousSchedulerTests: XCTestCase {
    func testHopOnlyTuningProducesHopsWithinDelayBounds() {
        var tuning = PersonalityTuning.default
        tuning.floatChance = 0
        var rng = SeededRandomSource(seed: 7)
        for _ in 0..<200 {
            let decision = AutonomousScheduler.nextDecision(using: &rng, tuning: tuning)
            XCTAssertEqual(decision.action, .hop)
            XCTAssertTrue((tuning.hopMinDelay...tuning.hopMaxDelay).contains(decision.delay))
        }
    }

    func testFloatOnlyTuningProducesFloatsWithinDelayBounds() {
        var tuning = PersonalityTuning.default
        tuning.floatChance = 1
        var rng = SeededRandomSource(seed: 9)
        for _ in 0..<200 {
            let decision = AutonomousScheduler.nextDecision(using: &rng, tuning: tuning)
            XCTAssertEqual(decision.action, .float)
            XCTAssertTrue((tuning.floatMinInterval...tuning.floatMaxInterval).contains(decision.delay))
        }
    }

    func testFloatFrequencyIsRareButPresent() {
        let tuning = PersonalityTuning.default  // floatChance 0.2
        var rng = SeededRandomSource(seed: 42)
        var floats = 0
        for _ in 0..<2000 {
            if AutonomousScheduler.nextDecision(using: &rng, tuning: tuning).action == .float {
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
            let da = AutonomousScheduler.nextDecision(using: &a, tuning: tuning)
            let db = AutonomousScheduler.nextDecision(using: &b, tuning: tuning)
            XCTAssertEqual(da.action, db.action)
            XCTAssertEqual(da.delay, db.delay)
        }
    }
}
