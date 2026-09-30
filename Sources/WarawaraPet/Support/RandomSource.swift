import Foundation

protocol RandomSource {
    mutating func nextUnit() -> Double
}

struct SystemRandomSource: RandomSource {
    private var generator = SystemRandomNumberGenerator()

    mutating func nextUnit() -> Double {
        Double.random(in: 0..<1, using: &generator)
    }
}

struct SeededRandomSource: RandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

enum RandomBounds {
    static func randomDelay(
        in range: ClosedRange<TimeInterval>,
        using rng: inout some RandomSource
    ) -> TimeInterval {
        let lower = Swift.min(range.lowerBound, range.upperBound)
        let span = abs(range.upperBound - range.lowerBound)
        return lower + rng.nextUnit() * span
    }

    static func randomCGFloat(
        in range: ClosedRange<CGFloat>,
        using rng: inout some RandomSource
    ) -> CGFloat {
        let lower = Swift.min(range.lowerBound, range.upperBound)
        let span = abs(range.upperBound - range.lowerBound)
        return lower + CGFloat(rng.nextUnit()) * span
    }
}
