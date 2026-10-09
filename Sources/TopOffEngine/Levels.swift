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

extension TopOffLevel {
    /// Whether any bottle starts with concealed layers.
    public var hasHiddenLayers: Bool {
        board.containers.contains { $0.hiddenLayers > 0 }
    }

    /// 1 to 3 stars from how close the move count is to the shortest solution. Concealed levels
    /// allow more slack because the player cannot see what they are pouring onto.
    public func stars(forMoves moves: Int) -> Int {
        let par = Double(max(solution.count, 1))
        let slack = hasHiddenLayers ? 1.6 : 1.25
        if Double(moves) <= (par * slack).rounded(.up) { return 3 }
        if Double(moves) <= (par * (slack + 0.6)).rounded(.up) { return 2 }
        return 1
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

    /// Boards were chosen offline by *playability*, not solution length (see `DifficultyProbe`).
    /// `luck` is how often random tapping wins; `trap` is how often six random pours leave the board
    /// unsolvable. Two spare bottles make a board easy however long its solution is, so tension comes
    /// from one spare bottle, concealed layers, and bigger boards. Levels 3, 5 and 6 are deliberately
    /// gentle: they introduce 3-bottle boards, concealed layers and a bigger board without a wall.
    /// Levels with `visibleLayers` introduce concealed layers, which are revealed once everything above
    /// them is poured away.
    private static let generated: [GeneratedSpec] = [
        GeneratedSpec(seed: 11, colors: 3, capacity: 3, empties: 2),                    // 3: luck 100, easy start
        GeneratedSpec(seed: 5, colors: 3, capacity: 3, empties: 1),                     // 4: luck 65 trap 21, first tight board
        GeneratedSpec(seed: 1, colors: 3, capacity: 3, empties: 2, visibleLayers: 2),   // 5: luck 100, hidden layers introduced gently
        GeneratedSpec(seed: 7, colors: 4, capacity: 4, empties: 2),                     // 6: bigger board, relaxed
        GeneratedSpec(seed: 113, colors: 4, capacity: 3, empties: 1),                   // 7: luck 46 trap 53, first real puzzle
        GeneratedSpec(seed: 1366, colors: 5, capacity: 4, empties: 2, visibleLayers: 2), // 8: luck 35 trap 8
        GeneratedSpec(seed: 253, colors: 5, capacity: 4, empties: 1, visibleLayers: 2), // 9: luck 37 trap 65, tight and concealed
        GeneratedSpec(seed: 534, colors: 6, capacity: 4, empties: 2, visibleLayers: 2), // 10: luck 24 trap 20
        GeneratedSpec(seed: 603, colors: 6, capacity: 4, empties: 2, visibleLayers: 1), // 11: luck 31 trap 1, only tops visible
        GeneratedSpec(seed: 2, colors: 4, capacity: 4, empties: 1)                      // 12: luck 3 trap 63, the finale
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
