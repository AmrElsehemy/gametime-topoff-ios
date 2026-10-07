/// One play-through of a level: current board plus undo history.
/// Pure state; rendering, haptics and monetization live outside the engine.
public struct Game: Sendable {
    public let initialBoard: Board
    public private(set) var board: Board
    public private(set) var history: [Pour] = []

    public init(board: Board) {
        self.initialBoard = board
        self.board = board
    }

    public var isSolved: Bool { board.isSolved }
    public var canUndo: Bool { !history.isEmpty }
    public var moveCount: Int { history.count }

    @discardableResult
    public mutating func pour(_ move: Move) throws -> Pour {
        let pour = try board.apply(move)
        history.append(pour)
        return pour
    }

    @discardableResult
    public mutating func undo() -> Pour? {
        guard let pour = history.popLast() else { return nil }
        board.revert(pour)
        return pour
    }

    public mutating func restart() {
        board = initialBoard
        history.removeAll()
    }
}
