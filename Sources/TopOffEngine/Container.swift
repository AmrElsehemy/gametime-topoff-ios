/// A colour of liquid. Identity only; palette and patterns are a rendering concern.
public struct LiquidColor: Hashable, Codable, Sendable {
    public let id: Int

    public init(_ id: Int) {
        self.id = id
    }
}

/// A fixed-capacity container. `layers` run bottom to top, one entry per unit of liquid.
public struct Container: Equatable, Codable, Sendable {
    public let capacity: Int
    public private(set) var layers: [LiquidColor]

    public init(capacity: Int, layers: [LiquidColor] = []) {
        precondition(capacity > 0, "Container capacity must be positive")
        precondition(layers.count <= capacity, "Container layers exceed capacity")
        self.capacity = capacity
        self.layers = layers
    }

    public var isEmpty: Bool { layers.isEmpty }
    public var isFull: Bool { layers.count == capacity }
    public var freeSpace: Int { capacity - layers.count }
    public var topColor: LiquidColor? { layers.last }

    /// Number of contiguous units of the top colour.
    public var topRunLength: Int {
        guard let top = layers.last else { return 0 }
        return layers.reversed().prefix { $0 == top }.count
    }

    public var isUniform: Bool {
        guard let first = layers.first else { return true }
        return layers.allSatisfy { $0 == first }
    }

    /// Solved containers are empty, or completely full of a single colour.
    public var isSolved: Bool { isEmpty || (isFull && isUniform) }

    mutating func removeTop(_ count: Int) {
        layers.removeLast(count)
    }

    mutating func addOnTop(_ color: LiquidColor, count: Int) {
        layers.append(contentsOf: repeatElement(color, count: count))
    }
}
