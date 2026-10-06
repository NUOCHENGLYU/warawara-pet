import XCTest
@testable import WarawaraPet

final class SleepinessEvaluatorTests: XCTestCase {
    private var tuning: PersonalityTuning {
        var t = PersonalityTuning.default
        t.sleepyTimeout = 240
        t.sleepTimeout = 480
        return t
    }

    func testIdleBelowThresholdDoesNothing() {
        XCTAssertNil(SleepinessEvaluator.decision(state: .idle, idleSeconds: 239.9, tuning: tuning))
    }

    func testIdleAtThresholdEntersSleepy() {
        XCTAssertEqual(
            SleepinessEvaluator.decision(state: .idle, idleSeconds: 240, tuning: tuning),
            .enterSleepy
        )
    }

    func testSleepyBelowSleepTimeoutDoesNothing() {
        XCTAssertNil(SleepinessEvaluator.decision(state: .sleepy, idleSeconds: 479, tuning: tuning))
    }

    func testSleepyAtSleepTimeoutEntersSleeping() {
        XCTAssertEqual(
            SleepinessEvaluator.decision(state: .sleepy, idleSeconds: 480, tuning: tuning),
            .enterSleeping
        )
    }

    func testActivityResumesFromSleepy() {
        XCTAssertEqual(
            SleepinessEvaluator.decision(state: .sleepy, idleSeconds: 30, tuning: tuning),
            .returnToIdle
        )
    }

    func testOtherStatesAreIgnored() {
        for state in [PetState.hop, .float, .curious, .clicked, .dragged, .settling, .sleeping] {
            XCTAssertNil(SleepinessEvaluator.decision(state: state, idleSeconds: 1000, tuning: tuning))
        }
    }
}
