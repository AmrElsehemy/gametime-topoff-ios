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
        ),
        TopOffLevel(
            id: 3,
            board: Board(containers: [
                Container(capacity: 3, layers: [red, blue, green]),
                Container(capacity: 3, layers: [green, red, blue]),
                Container(capacity: 3, layers: [blue, green, red]),
                Container(capacity: 3),
                Container(capacity: 3)
            ]),
            solution: [
                Move(from: 0, to: 3),
                Move(from: 1, to: 0),
                Move(from: 2, to: 1),
                Move(from: 2, to: 3),
                Move(from: 0, to: 2),
                Move(from: 1, to: 0),
                Move(from: 1, to: 3)
            ]
        ),
        TopOffLevel(
            id: 4,
            board: Board(containers: [
                Container(capacity: 3, layers: [red, blue, red]),
                Container(capacity: 3, layers: [blue, green, green]),
                Container(capacity: 3, layers: [green, blue, red]),
                Container(capacity: 3),
                Container(capacity: 3)
            ]),
            solution: [
                Move(from: 0, to: 3),
                Move(from: 2, to: 3),
                Move(from: 2, to: 0),
                Move(from: 1, to: 2),
                Move(from: 0, to: 1),
                Move(from: 0, to: 3)
            ]
        ),
        TopOffLevel(
            id: 5,
            board: Board(containers: [
                Container(capacity: 3, layers: [red, blue, green]),
                Container(capacity: 3, layers: [blue, green, red]),
                Container(capacity: 3, layers: [green, red, blue]),
                Container(capacity: 3),
                Container(capacity: 3)
            ]),
            solution: [
                Move(from: 0, to: 3),
                Move(from: 2, to: 0),
                Move(from: 1, to: 2),
                Move(from: 1, to: 3),
                Move(from: 0, to: 1),
                Move(from: 2, to: 0),
                Move(from: 2, to: 3)
            ]
        )
    ]
}
