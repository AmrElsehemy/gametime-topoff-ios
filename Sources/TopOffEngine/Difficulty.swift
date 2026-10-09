/// Measures how hard a board is to play, which shortest-solution length alone does not.
///
/// A board with two spare bottles can have a long optimal solution and still be won by random
/// tapping nearly every time, so it is not a puzzle. These probes use seeded random play, so the
/// same board gives the same numbers on every device (the daily puzzle depends on that).
public enum DifficultyProbe {
    /// Percentage (0-100) of random-play runs that solve the board within `moveBudget` pours.
    /// High means easy to win by luck; near 0 means the player has to think.
    public static func luckRate(
        _ board: Board,
        trials: Int = 60,
        moveBudget: Int = 80,
        seed: UInt64 = 1
    ) -> Int {
        guard trials > 0 else { return 0 }
        var rng = SeededGenerator(seed: seed)
        var solved = 0
        for _ in 0..<trials {
            var game = Game(board: board)
            var moves = 0
            while !game.isSolved, moves < moveBudget {
                guard let move = legalMoves(game.board).randomElement(using: &rng) else { break }
                _ = try? game.pour(move)
                moves += 1
            }
            if game.isSolved { solved += 1 }
        }
        return solved * 100 / trials
    }

    /// Percentage (0-100) of random openings of `probeMoves` pours that leave the board unsolvable.
    /// High means easy to get stuck, so the level is unforgiving.
    public static func trapRate(
        _ board: Board,
        trials: Int = 25,
        probeMoves: Int = 6,
        seed: UInt64 = 2,
        stateLimit: Int = 250_000
    ) -> Int {
        guard trials > 0 else { return 0 }
        var rng = SeededGenerator(seed: seed)
        var stuck = 0
        for _ in 0..<trials {
            var game = Game(board: board)
            for _ in 0..<probeMoves {
                guard let move = legalMoves(game.board).randomElement(using: &rng) else { break }
                _ = try? game.pour(move)
            }
            if Solver.solve(game.board, stateLimit: stateLimit) == nil { stuck += 1 }
        }
        return stuck * 100 / trials
    }

    static func legalMoves(_ board: Board) -> [Move] {
        var moves: [Move] = []
        for from in board.containers.indices {
            for to in board.containers.indices where from != to {
                if (try? board.validate(Move(from: from, to: to))) != nil {
                    moves.append(Move(from: from, to: to))
                }
            }
        }
        return moves
    }
}
