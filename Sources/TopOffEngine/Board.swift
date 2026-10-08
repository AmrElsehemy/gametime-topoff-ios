public struct Move: Equatable, Codable, Sendable {
    public let from: Int
    public let to: Int

    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }
}

/// A completed pour, recorded so it can be undone and replayed.
public struct Pour: Equatable, Codable, Sendable {
    public let move: Move
    public let color: LiquidColor
    public let amount: Int
    /// Source bottle's concealed-layer count before the pour, so undo can hide layers again.
    public let sourceHiddenBefore: Int
}

public enum PourError: Error, Equatable, Sendable {
    case invalidContainer
    case sameContainer
    case sourceEmpty
    case targetFull
    case colorMismatch
}

public struct Board: Equatable, Codable, Sendable {
    public private(set) var containers: [Container]

    public init(containers: [Container]) {
        self.containers = containers
    }

    public var isSolved: Bool { containers.allSatisfy(\.isSolved) }

    /// Appends an empty bottle. It goes last so indices held by recorded pours stay valid.
    public mutating func addEmptyContainer(capacity: Int) {
        containers.append(Container(capacity: capacity))
    }

    /// How much liquid `move` would transfer, or why it is illegal.
    public func validate(_ move: Move) throws -> Int {
        guard containers.indices.contains(move.from), containers.indices.contains(move.to) else {
            throw PourError.invalidContainer
        }
        guard move.from != move.to else { throw PourError.sameContainer }

        let source = containers[move.from]
        let target = containers[move.to]
        guard let color = source.topColor else { throw PourError.sourceEmpty }
        guard !target.isFull else { throw PourError.targetFull }
        if let targetTop = target.topColor, targetTop != color {
            throw PourError.colorMismatch
        }
        return min(source.topRunLength, target.freeSpace)
    }

    @discardableResult
    mutating func apply(_ move: Move) throws -> Pour {
        let amount = try validate(move)
        let color = containers[move.from].topColor!
        let hiddenBefore = containers[move.from].hiddenLayers
        containers[move.from].removeTop(amount)
        containers[move.to].addOnTop(color, count: amount)
        return Pour(move: move, color: color, amount: amount, sourceHiddenBefore: hiddenBefore)
    }

    mutating func revert(_ pour: Pour) {
        containers[pour.move.to].removeTop(pour.amount)
        containers[pour.move.from].addOnTop(pour.color, count: pour.amount)
        containers[pour.move.from].restoreHiddenLayers(pour.sourceHiddenBefore)
    }
}
