/// Deterministic pseudo-random source so any generated level can be rebuilt from its seed.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum LevelGenerator {
    /// A shuffled board of `colors` bottles' worth of liquid plus `empties` empty bottles.
    /// No bottle starts already solved. The result is not guaranteed solvable; check with `Solver`.
    public static func board(seed: UInt64, colors: Int, capacity: Int, empties: Int) -> Board {
        var rng = SeededGenerator(seed: seed)
        while true {
            var units: [LiquidColor] = []
            for color in 1...colors {
                units.append(contentsOf: repeatElement(LiquidColor(color), count: capacity))
            }
            units.shuffle(using: &rng)

            var containers: [Container] = []
            for index in 0..<colors {
                let slice = Array(units[(index * capacity)..<((index + 1) * capacity)])
                containers.append(Container(capacity: capacity, layers: slice))
            }
            guard !containers.contains(where: \.isSolved) else { continue }
            for _ in 0..<empties { containers.append(Container(capacity: capacity)) }
            return Board(containers: containers)
        }
    }
}
