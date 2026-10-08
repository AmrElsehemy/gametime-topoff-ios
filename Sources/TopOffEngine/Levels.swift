public struct TopOffLevel: Equatable, Sendable {
    public let id: Int
    public let board: Board
    public let solution: [Move]

    public init(id: Int, board: Board, solution: [Move]) {
        self.id = id
        self.board = board
        self.solution = solution
    }
}

public enum TopOffLevels {
    private static let red = LiquidColor(1)
    private static let blue = LiquidColor(2)
    private static let green = LiquidColor(3)

    public static let handcrafted: [TopOffLevel] = [
        TopOffLevel(
            id: 1,
            board: Board(containers: [
                Container(capacity: 2, layers: [red, blue]),
                Container(capacity: 2, layers: [blue, red]),
                Container(capacity: 2)
            ]),
            solution: [
                Move(from: 0, to: 2),
                Move(from: 1, to: 0),
                Move(from: 1, to: 2)
            ]
        ),
        TopOffLevel(
            id: 2,
            board: Board(containers: [
                Container(capacity: 2, layers: [red, blue]),
                Container(capacity: 2, layers: [green, red]),
                Container(capacity: 2, layers: [blue, green]),
                Container(capacity: 2)
            ]),
            solution: [
                Move(from: 0, to: 3),
                Move(from: 1, to: 0),
                Move(from: 2, to: 1),
                Move(from: 2, to: 3)
            ]
        )
    ]

    private struct GeneratedSpec {
        let seed: UInt64
        let colors: Int
        let capacity: Int
        let empties: Int
    }

    /// Seeds were picked offline with `Solver` for a steady difficulty ramp; see `testCampaignRamp`.
    private static let generated: [GeneratedSpec] = [
        GeneratedSpec(seed: 1, colors: 3, capacity: 3, empties: 2),   // 7 moves
        GeneratedSpec(seed: 2, colors: 4, capacity: 3, empties: 2),   // 9
        GeneratedSpec(seed: 2, colors: 4, capacity: 4, empties: 2),   // 14
        GeneratedSpec(seed: 1, colors: 5, capacity: 4, empties: 2),   // 16
        GeneratedSpec(seed: 8, colors: 5, capacity: 4, empties: 1),   // 17, one spare bottle
        GeneratedSpec(seed: 29, colors: 6, capacity: 4, empties: 2),  // 20
        GeneratedSpec(seed: 29, colors: 6, capacity: 4, empties: 1)   // 21, one spare bottle
    ]

    /// The full ramp: two handcrafted teaching levels, then solver-verified generated levels.
    public static let campaign: [TopOffLevel] = {
        var levels = handcrafted
        for spec in generated {
            let board = LevelGenerator.board(
                seed: spec.seed,
                colors: spec.colors,
                capacity: spec.capacity,
                empties: spec.empties
            )
            guard let solution = Solver.solve(board) else {
                preconditionFailure("Generated level with seed \(spec.seed) is unsolvable")
            }
            levels.append(TopOffLevel(id: levels.count + 1, board: board, solution: solution))
        }
        return levels
    }()
}
