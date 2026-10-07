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
        XCTAssertEqual(levels.map(\.id), [1, 2, 3, 4, 5])

        for level in levels {
            var game = Game(board: level.board)
            XCTAssertFalse(game.isSolved, "Level \(level.id) should start unsolved")
            for move in level.solution {
                try game.pour(move)
            }
            XCTAssertTrue(game.isSolved, "Level \(level.id) reference solution should solve the board")
        }
    }

}
