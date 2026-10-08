import XCTest
@testable import TopOffEngine

final class TopOffEngineTests: XCTestCase {
    private let red = LiquidColor(1)
    private let blue = LiquidColor(2)

    func testTopRunLengthCountsContiguousTopColour() {
        let container = Container(capacity: 4, layers: [blue, red, red])
        XCTAssertEqual(container.topColor, red)
        XCTAssertEqual(container.topRunLength, 2)
        XCTAssertEqual(Container(capacity: 4).topRunLength, 0)
    }

    func testSolvedContainersAreEmptyOrFullAndUniform() {
        XCTAssertTrue(Container(capacity: 2).isSolved)
        XCTAssertTrue(Container(capacity: 2, layers: [red, red]).isSolved)
        XCTAssertFalse(Container(capacity: 3, layers: [red, red]).isSolved)
        XCTAssertFalse(Container(capacity: 2, layers: [red, blue]).isSolved)
    }

    func testPourMovesWholeTopRunWhenThereIsRoom() throws {
        var board = Board(containers: [
            Container(capacity: 4, layers: [blue, red, red]),
            Container(capacity: 4, layers: [red])
        ])
        let pour = try board.apply(Move(from: 0, to: 1))
        XCTAssertEqual(pour.amount, 2)
        XCTAssertEqual(board.containers[0].layers, [blue])
        XCTAssertEqual(board.containers[1].layers, [red, red, red])
    }

    func testPourIsLimitedByFreeSpace() throws {
        var board = Board(containers: [
            Container(capacity: 4, layers: [red, red, red]),
            Container(capacity: 4, layers: [blue, red, red])
        ])
        let pour = try board.apply(Move(from: 0, to: 1))
        XCTAssertEqual(pour.amount, 1)
        XCTAssertEqual(board.containers[0].layers, [red, red])
        XCTAssertTrue(board.containers[1].isFull)
    }

    func testIllegalPoursAreRejected() {
        let board = Board(containers: [
            Container(capacity: 2, layers: [red]),
            Container(capacity: 2, layers: [blue]),
            Container(capacity: 2),
            Container(capacity: 2, layers: [red, red])
        ])
        XCTAssertThrowsError(try board.validate(Move(from: 0, to: 0))) {
            XCTAssertEqual($0 as? PourError, .sameContainer)
        }
        XCTAssertThrowsError(try board.validate(Move(from: 2, to: 0))) {
            XCTAssertEqual($0 as? PourError, .sourceEmpty)
        }
        XCTAssertThrowsError(try board.validate(Move(from: 0, to: 3))) {
            XCTAssertEqual($0 as? PourError, .targetFull)
        }
        XCTAssertThrowsError(try board.validate(Move(from: 0, to: 1))) {
            XCTAssertEqual($0 as? PourError, .colorMismatch)
        }
        XCTAssertThrowsError(try board.validate(Move(from: 0, to: 9))) {
            XCTAssertEqual($0 as? PourError, .invalidContainer)
        }
    }

    func testUndoRestoresBoardExactly() throws {
        var game = Game(board: Board(containers: [
            Container(capacity: 3, layers: [blue, red, red]),
            Container(capacity: 3, layers: [red])
        ]))
        try game.pour(Move(from: 0, to: 1))
        XCTAssertEqual(game.moveCount, 1)
        XCTAssertNotNil(game.undo())
        XCTAssertEqual(game.board, game.initialBoard)
        XCTAssertFalse(game.canUndo)
        XCTAssertNil(game.undo())
    }

    func testIllegalMoveDoesNotChangeStateOrHistory() {
        var game = Game(board: Board(containers: [
            Container(capacity: 2, layers: [red]),
            Container(capacity: 2, layers: [blue])
        ]))
        XCTAssertThrowsError(try game.pour(Move(from: 0, to: 1)))
        XCTAssertEqual(game.board, game.initialBoard)
        XCTAssertEqual(game.moveCount, 0)
    }

    func testSolvingAndRestart() throws {
        var game = Game(board: Board(containers: [
            Container(capacity: 2, layers: [red, blue]),
            Container(capacity: 2, layers: [blue, red]),
            Container(capacity: 2)
        ]))
        XCTAssertFalse(game.isSolved)
        try game.pour(Move(from: 0, to: 2))   // blue -> empty
        try game.pour(Move(from: 1, to: 0))   // red  -> onto red
        try game.pour(Move(from: 1, to: 2))   // blue -> onto blue
        XCTAssertTrue(game.isSolved)
        game.restart()
        XCTAssertFalse(game.isSolved)
        XCTAssertEqual(game.moveCount, 0)
    }

    func testHandcraftedLevelsHaveStableIdsAndAllSolve() throws {
        let levels = TopOffLevels.handcrafted
        XCTAssertEqual(levels.map(\.id), [1, 2])

        for level in levels {
            var game = Game(board: level.board)
            XCTAssertFalse(game.isSolved, "Level \(level.id) should start unsolved")
            for move in level.solution {
                try game.pour(move)
            }
            XCTAssertTrue(game.isSolved, "Level \(level.id) reference solution should solve the board")
        }
    }

    func testCampaignRamp() throws {
        let levels = TopOffLevels.campaign
        XCTAssertEqual(levels.map(\.id), Array(1...levels.count))

        // Concealed-layer levels are shorter on paper but harder to play, so the length ramp
        // is only checked across fully visible levels.
        var previousLength = 0
        for level in levels {
            var game = Game(board: level.board)
            XCTAssertFalse(game.isSolved, "Level \(level.id) should start unsolved")
            for move in level.solution { try game.pour(move) }
            XCTAssertTrue(game.isSolved, "Level \(level.id) solution should solve the board")
            let hasHidden = level.board.containers.contains { $0.hiddenLayers > 0 }
            if hasHidden { continue }
            if level.id > 2 {
                XCTAssertGreaterThanOrEqual(level.solution.count + 3, previousLength, "Level \(level.id) should not be much easier than the last")
            }
            previousLength = level.solution.count
        }
    }

    func testSolverFindsShortestSolutionAndRejectsDeadBoards() {
        let level = TopOffLevels.handcrafted[0]
        XCTAssertEqual(Solver.solve(level.board)?.count, 3)

        let stuck = Board(containers: [
            Container(capacity: 2, layers: [LiquidColor(1), LiquidColor(2)]),
            Container(capacity: 2, layers: [LiquidColor(2), LiquidColor(1)])
        ])
        XCTAssertNil(Solver.solve(stuck))
    }


    func testHiddenLayersRevealOnlyWhenExposedAndUndoRestoresThem() throws {
        let red = LiquidColor(1), blue = LiquidColor(2)
        // Bottom to top: blue (hidden), red, red. Only the two reds are visible.
        let board = Board(containers: [
            Container(capacity: 3, layers: [blue, red, red], hiddenLayers: 1),
            Container(capacity: 3)
        ])
        XCTAssertEqual(board.containers[0].hiddenLayers, 1)
        XCTAssertEqual(board.containers[0].topRunLength, 2)

        var game = Game(board: board)
        try game.pour(Move(from: 0, to: 1))
        XCTAssertEqual(game.board.containers[0].layers, [blue])
        XCTAssertEqual(game.board.containers[0].hiddenLayers, 0, "Blue is exposed and now visible")

        game.undo()
        XCTAssertEqual(game.board.containers[0].hiddenLayers, 1, "Undo conceals it again")
        XCTAssertEqual(game.board, board)
    }

    func testConcealedLayersNeverJoinThePouredRun() {
        let red = LiquidColor(1)
        // Hidden red under a visible red must not move with it.
        let board = Board(containers: [
            Container(capacity: 3, layers: [red, red], hiddenLayers: 1),
            Container(capacity: 3)
        ])
        XCTAssertEqual(try? board.validate(Move(from: 0, to: 1)), 1)
    }

    func testStarsScaleWithMovesOverPar() {
        let level = TopOffLevels.campaign[4]   // fully visible, so par is the true shortest
        let par = level.solution.count
        XCTAssertEqual(level.stars(forMoves: par), 3)
        XCTAssertEqual(level.stars(forMoves: par * 3), 1)
        XCTAssertGreaterThanOrEqual(level.stars(forMoves: par + par / 2 + 1), 1)
        XCTAssertLessThanOrEqual(level.stars(forMoves: par + par / 2 + 1), 2)
    }

    func testExtraContainerKeepsHistoryAndRestartRemovesIt() throws {
        var game = Game(board: TopOffLevels.handcrafted[0].board)
        let before = game.board.containers.count
        try game.pour(Move(from: 0, to: 2))
        game.addExtraContainer()
        XCTAssertEqual(game.board.containers.count, before + 1)
        XCTAssertNotNil(game.undo(), "Undo still works after adding a bottle")
        game.restart()
        XCTAssertEqual(game.board.containers.count, before)
    }

    func testDailyPuzzleIsDeterministicSolvableAndFollowsTheWeek() throws {
        for day in 800..<814 {
            let first = DailyPuzzle.level(forDay: day)
            let second = DailyPuzzle.level(forDay: day)
            XCTAssertEqual(first.board, second.board, "Day \(day) must be the same every time")
            XCTAssertEqual(first.id, day)

            var game = Game(board: first.board)
            XCTAssertFalse(game.isSolved)
            for move in first.solution { try game.pour(move) }
            XCTAssertTrue(game.isSolved, "Day \(day) solution should solve the board")
        }
        XCTAssertNotEqual(DailyPuzzle.level(forDay: 800).board, DailyPuzzle.level(forDay: 801).board)
    }

    func testDayNumberCountsCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let jan1 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        XCTAssertEqual(DailyPuzzle.dayNumber(for: jan1, calendar: calendar), 0)
        let later = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1, hour: 23))!
        XCTAssertEqual(DailyPuzzle.dayNumber(for: later, calendar: calendar), 60)
    }
}
