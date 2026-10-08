/// Breadth-first solver. Returns a shortest solution, or nil if the board is unsolvable
/// or the search exceeds `stateLimit` distinct positions. It plays by the player's rules,
/// so concealed layers limit how much a pour can move, but it sees every colour.
public enum Solver {
    public static func solve(_ board: Board, stateLimit: Int = 2_000_000) -> [Move]? {
        let start = board.containers

        // Bottle order never matters for solvability, so positions are keyed by their sorted form.
        func key(_ state: [Container]) -> [UInt8] {
            var rows: [[UInt8]] = state.map { bottle in
                bottle.layers.map { UInt8($0.id) } + [254, UInt8(bottle.hiddenLayers)]
            }
            rows.sort { $0.lexicographicallyPrecedes($1) }
            var flat: [UInt8] = []
            for row in rows {
                flat.append(contentsOf: row)
                flat.append(255)
            }
            return flat
        }

        struct Node {
            let state: [Container]
            let parent: Int
            let move: Move
        }

        if start.allSatisfy(\.isSolved) { return [] }
        var nodes = [Node(state: start, parent: -1, move: Move(from: 0, to: 0))]
        var seen: Set<[UInt8]> = [key(start)]

        var head = 0
        while head < nodes.count {
            let state = nodes[head].state

            for from in state.indices {
                let source = state[from]
                guard let top = source.topColor else { continue }
                // Pouring a uniform bottle into an empty one only relocates it.
                let sourceIsUniform = source.isUniform

                for to in state.indices where to != from {
                    let target = state[to]
                    guard !target.isFull else { continue }
                    if let targetTop = target.topColor, targetTop != top { continue }
                    if sourceIsUniform, target.isEmpty { continue }

                    let amount = min(source.topRunLength, target.freeSpace)
                    var next = state
                    next[from].removeTop(amount)
                    next[to].addOnTop(top, count: amount)

                    guard seen.insert(key(next)).inserted else { continue }
                    nodes.append(Node(state: next, parent: head, move: Move(from: from, to: to)))

                    if next.allSatisfy(\.isSolved) {
                        var moves: [Move] = []
                        var cursor = nodes.count - 1
                        while nodes[cursor].parent >= 0 {
                            moves.append(nodes[cursor].move)
                            cursor = nodes[cursor].parent
                        }
                        return moves.reversed()
                    }
                    if nodes.count > stateLimit { return nil }
                }
            }
            head += 1
        }
        return nil
    }
}
