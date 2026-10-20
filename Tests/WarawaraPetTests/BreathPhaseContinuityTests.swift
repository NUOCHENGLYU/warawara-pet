import XCTest
@testable import WarawaraPet

/// Continuous breathing-phase verification: the OLD absolute-time
/// formula `(time / period) % 1` is proven discontinuous whenever the
/// period follows the easing drowsiness; the NEW accumulator
/// `phase = (phase + dt / period) % 1` is proven continuous across
/// idle → sleepy → sleeping → clicked → idle, 5 minutes of sleep,
/// long-suspension jumps, cycle boundaries, and 30 Hz vs 60 Hz sampling.
final class BreathPhaseContinuityTests: XCTestCase {
    private let base = WarawaraExpressionDriver.breathBasePeriod
    private let extra = WarawaraExpressionDriver.breathSleepyExtraPerDrowsiness

    /// The retired production formula (absolute-time division), kept here
    /// ONLY to prove the defect it caused. Realistic absolute time:
    /// timeIntervalSinceReferenceDate is ~7e8 s, so even a tiny period
    /// change flips the remainder almost arbitrarily.
    private func legacyPhase(at time: TimeInterval, period: TimeInterval) -> CGFloat {
        let phase = (time / period).truncatingRemainder(dividingBy: 1)
        return CGFloat(phase < 0 ? phase + 1 : phase)
    }

    /// Wrap-corrected phase distance in 0...0.5.
    private func circularDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = abs(a - b)
        d = min(d, 1 - d)
        return d
    }

    private func inputs(state: PetState) -> WarawaraExpressionInputs {
        WarawaraExpressionInputs(state: state)
    }

    private func date(at t: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 720_000_000 + t)
    }

    /// Drives the REAL driver model at the given dt for `count` ticks,
    /// continuing an absolute timeline from `start`. Appends every
    /// published breathPhase and counts cycle wraps.
    @discardableResult
    private func driveModel(
        _ model: WarawaraExpressionDriverModel,
        state: PetState,
        dt: TimeInterval,
        ticks: Int,
        start: TimeInterval,
        phases: inout [CGFloat],
        wraps: inout Int
    ) -> TimeInterval {
        for index in 0..<ticks {
            model.tick(at: date(at: start + Double(index) * dt), inputs: inputs(state: state))
            let phase = model.animatorParameters.breathPhase
            if let previous = phases.last, previous > 0.9, phase < 0.1 {
                wraps += 1
            }
            phases.append(phase)
        }
        return start + Double(ticks) * dt
    }

    // MARK: - The old formula was discontinuous; the new one is not

    func testLegacyAbsoluteTimeFormulaJumpsWhileAccumulatorStaysSmooth() {
        // Drowsiness eases 0 -> 1 over 30 s (the real sleep-entry ramp),
        // sampled at 60 Hz, at a realistic absolute reference time.
        let startTime: TimeInterval = 720_000_000
        var drowsiness: CGFloat = 0
        var legacyMax: CGFloat = 0
        var accumulatorMax: CGFloat = 0
        var phase: CGFloat = 0
        var previousLegacy = legacyPhase(at: startTime, period: base)
        var previousAccumulator = phase
        for index in 0..<(30 * 60) {
            let t = startTime + Double(index) / 60.0
            drowsiness = min(CGFloat(index) / CGFloat(60 * 30), 1)
            let period = base + extra * drowsiness

            let legacy = legacyPhase(at: t, period: period)
            legacyMax = max(legacyMax, circularDelta(previousLegacy, legacy))
            previousLegacy = legacy

            phase = WarawaraExpressionDriver.advanceBreathPhase(
                phase, by: 1.0 / 60.0, period: period
            )
            accumulatorMax = max(accumulatorMax, circularDelta(previousAccumulator, phase))
            previousAccumulator = phase
        }
        XCTAssertGreaterThan(legacyMax, 0.5,
            "the retired absolute-time formula jumps more than half a cycle during the ramp (was \(legacyMax))")
        XCTAssertLessThan(accumulatorMax, 0.005,
            "the accumulator never steps more than dt/period (was \(accumulatorMax))")
    }

    // MARK: - Full sleep cycle through the real driver model

    func testModelBreathPhaseIsContinuousAcrossTheWholeSleepCycle() {
        let model = WarawaraExpressionDriverModel()
        var phases: [CGFloat] = []
        var wraps = 0
        let dt = 1.0 / 60.0
        var time: TimeInterval = 0

        // idle -> sleepy -> sleeping -> (5 minutes of sleep) -> clicked -> idle
        time = driveModel(model, state: .idle, dt: dt, ticks: 120, start: time, phases: &phases, wraps: &wraps)
        time = driveModel(model, state: .sleepy, dt: dt, ticks: 240, start: time, phases: &phases, wraps: &wraps)
        time = driveModel(model, state: .sleeping, dt: dt, ticks: 60 * 300, start: time, phases: &phases, wraps: &wraps)
        time = driveModel(model, state: .clicked, dt: dt, ticks: 60, start: time, phases: &phases, wraps: &wraps)
        _ = driveModel(model, state: .idle, dt: dt, ticks: 120, start: time, phases: &phases, wraps: &wraps)

        XCTAssertEqual(phases.count, 120 + 240 + 60 * 300 + 60 + 120)
        var maxJump: CGFloat = 0
        for index in 1..<phases.count {
            XCTAssertTrue(phases[index] >= 0 && phases[index] < 1, "phase stays wrapped")
            maxJump = max(maxJump, circularDelta(phases[index - 1], phases[index]))
        }
        XCTAssertLessThan(maxJump, 0.005,
            "no frame-to-frame phase jump anywhere in the sleep cycle (was \(maxJump))")

        // 5 minutes of sleep at ~6.5 s period -> about 46 full cycles.
        XCTAssertGreaterThanOrEqual(wraps, 40)
        XCTAssertLessThanOrEqual(wraps, 52)
    }

    func testBreathPhaseSurvivesLongSuspensionJumps() {
        let model = WarawaraExpressionDriverModel()
        var phases: [CGFloat] = []
        var wraps = 0
        let dt = 1.0 / 60.0
        let elapsed = driveModel(model, state: .sleeping, dt: dt, ticks: 120, start: 0,
                                 phases: &phases, wraps: &wraps)
        let before = phases.last!

        // The machine slept for hours: the next frame's dt is clamped to
        // 0.1 s by the driver, so the phase advances at most 0.1/base.
        for jump in [3600.0, 8 * 3600.0, 24 * 3600.0] {
            model.tick(at: date(at: elapsed + jump), inputs: inputs(state: .sleeping))
            let after = model.animatorParameters.breathPhase
            XCTAssertLessThanOrEqual(circularDelta(before, after), 0.1 / base + 0.0001,
                "a \(jump)s suspension advances the phase by at most the clamped dt")
        }

        // Repeated ticks with the SAME date never double-step.
        let sameDate = date(at: elapsed + 24 * 3600.0 + 1)
        model.tick(at: sameDate, inputs: inputs(state: .sleeping))
        let once = model.animatorParameters.breathPhase
        model.tick(at: sameDate, inputs: inputs(state: .sleeping))
        XCTAssertEqual(model.animatorParameters.breathPhase, once,
            "repeated ticks with the same date are no-ops")
    }

    func testPeriodChangeNeverResetsThePhase() {
        // Period 4 -> 6.5 mid-cycle: the phase must simply slow down, not
        // restart from wherever the absolute-time remainder happened to
        // land.
        var phase: CGFloat = 0.7
        for _ in 0..<60 {
            phase = WarawaraExpressionDriver.advanceBreathPhase(phase, by: 1.0 / 60.0, period: base)
        }
        let beforeSwitch = phase
        phase = WarawaraExpressionDriver.advanceBreathPhase(phase, by: 1.0 / 60.0, period: base + extra)
        XCTAssertLessThan(circularDelta(beforeSwitch, phase), 0.005,
            "a period change is a frequency change, never a phase reset")
    }

    func testSamplingRateIndependenceAt30And60Hz() {
        let model30 = WarawaraExpressionDriverModel()
        let model60 = WarawaraExpressionDriverModel()
        var p30: [CGFloat] = []
        var p60: [CGFloat] = []
        var w30 = 0
        var w60 = 0
        _ = driveModel(model30, state: .sleeping, dt: 1.0 / 30.0, ticks: 30 * 60, start: 0, phases: &p30, wraps: &w30)
        _ = driveModel(model60, state: .sleeping, dt: 1.0 / 60.0, ticks: 60 * 60, start: 0, phases: &p60, wraps: &w60)

        // 60 s at the sleeping period (6.5 s): about 9 full cycles.
        XCTAssertGreaterThanOrEqual(w30, 8)
        XCTAssertLessThanOrEqual(w30, 11)
        XCTAssertGreaterThanOrEqual(w60, 8)
        XCTAssertLessThanOrEqual(w60, 11)
        XCTAssertLessThanOrEqual(abs(w30 - w60), 1,
            "30 Hz and 60 Hz sampling measure the same breathing frequency")
    }

    // MARK: - Sleeping mouth follows the unified continuous cycle

    func testSleepingMouthFollowsTheContinuousBreathCycle() {
        // The sleeping mouth target oscillates smoothly with the unified
        // breath phase: gentle swell and shrink, never two discrete sizes.
        var samples: [CGFloat] = []
        for step in 0...24 {
            let phase = CGFloat(step) / 16.0 // 0...1.5 cycles
            let target = WarawaraExpressionMapper.targetParameters(
                for: WarawaraExpressionContext(
                    inputs: WarawaraExpressionInputs(state: .sleeping),
                    breathPhase: phase
                )
            )
            samples.append(target.mouthOpenAmount)
        }
        let maxValue = samples.max()!
        let minValue = samples.min()!
        XCTAssertEqual(maxValue, 0.30, accuracy: 0.01)
        XCTAssertEqual(minValue, 0.12, accuracy: 0.01)
        XCTAssertGreaterThan(maxValue - minValue, 0.15,
            "the sleeping mouth visibly swells and shrinks with the breath")
        var maxima = 0
        var minima = 0
        for index in 1..<(samples.count - 1) {
            if samples[index] > samples[index - 1], samples[index] > samples[index + 1] { maxima += 1 }
            if samples[index] < samples[index - 1], samples[index] < samples[index + 1] { minima += 1 }
        }
        XCTAssertEqual(maxima, 1, "one smooth peak per breathing cycle")
        XCTAssertEqual(minima, 1, "one smooth trough per breathing cycle")
    }
}
