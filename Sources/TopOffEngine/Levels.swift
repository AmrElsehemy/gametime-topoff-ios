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
        /// Top layers of each bottle that start visible. nil means everything is visible.
        var visibleLayers: Int?

        init(seed: UInt64, colors: Int, capacity: Int, empties: Int, visibleLayers: Int? = nil) {
            self.seed = seed
            self.colors = colors
            self.capacity = capacity
            self.empties = empties
            self.visibleLayers = visibleLayers
        }
    }

    /// Seeds were picked offline with `Solver` for a steady difficulty ramp; see `testCampaignRamp`.
    /// Comments give the shortest solution length. Levels with `visibleLayers` introduce
    /// concealed layers, which are revealed once everything above them is poured away.
    private static let generated: [GeneratedSpec] = [
        GeneratedSpec(seed: 1, colors: 3, capacity: 3, empties: 2),                     // 3: 7
        GeneratedSpec(seed: 2, colors: 4, capacity: 3, empties: 2),                     // 4: 9
        GeneratedSpec(seed: 2, colors: 4, capacity: 4, empties: 2),                     // 5: 14
        GeneratedSpec(seed: 1, colors: 3, capacity: 3, empties: 2, visibleLayers: 2),   // 6: 7, first mystery
        GeneratedSpec(seed: 1, colors: 5, capacity: 4, empties: 2),                     // 7: 16
        GeneratedSpec(seed: 1, colors: 4, capacity: 4, empties: 2, visibleLayers: 2),   // 8: 12
        GeneratedSpec(seed: 8, colors: 5, capacity: 4, empties: 1),                     // 9: 17, one spare bottle
        GeneratedSpec(seed: 2, colors: 5, capacity: 4, empties: 2, visibleLayers: 2),   // 10: 15
        GeneratedSpec(seed: 29, colors: 6, capacity: 4, empties: 2),                    // 11: 20
        GeneratedSpec(seed: 4, colors: 6, capacity: 4, empties: 2, visibleLayers: 1)    // 12: 21, only tops visible
    ]

    /// The full ramp: two handcrafted teaching levels, then solver-verified generated levels.
    public static let campaign: [TopOffLevel] = {
        var levels = handcrafted
        for spec in generated {
            let board = LevelGenerator.board(
                seed: spec.seed,
                colors: spec.colors,
                capacity: spec.capacity,
                empties: spec.empties,
                visibleLayers: spec.visibleLayers
            )
            guard let solution = Solver.solve(board) else {
                preconditionFailure("Generated level with seed \(spec.seed) is unsolvable")
            }
            levels.append(TopOffLevel(id: levels.count + 1, board: board, solution: solution))
        }
        return levels
    }()
}
