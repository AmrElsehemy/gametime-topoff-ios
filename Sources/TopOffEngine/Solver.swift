/// Breadth-first solver. Returns a shortest solution, or nil if the board is unsolvable
/// or the search exceeds `stateLimit` distinct positions.
public enum Solver {
    public static func solve(_ board: Board, stateLimit: Int = 2_000_000) -> [Move]? {
        let capacities = board.containers.map(\.capacity)
        let start = board.containers.map { $0.layers.map { UInt8($0.id) } }

        func isSolved(_ state: [[UInt8]]) -> Bool {
            for (index, bottle) in state.enumerated() {
                if bottle.isEmpty { continue }
                guard bottle.count == capacities[index], bottle.allSatisfy({ $0 == bottle[0] }) else {
                    return false
                }
            }
            return true
        }

        // Bottle order never matters for solvability, so positions are keyed by their sorted form.
        func key(_ state: [[UInt8]]) -> [UInt8] {
            var flat: [UInt8] = []
            for bottle in state.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                flat.append(contentsOf: bottle)
                flat.append(255)
            }
            return flat
        }

        struct Node {
            let state: [[UInt8]]
            let parent: Int
            let move: Move
        }

        var nodes = [Node(state: start, parent: -1, move: Move(from: 0, to: 0))]
        var seen: Set<[UInt8]> = [key(start)]
        if isSolved(start) { return [] }

        var head = 0
        while head < nodes.count {
            let node = nodes[head]
            let state = node.state

            for from in state.indices {
                let source = state[from]
                guard let top = source.last else { continue }
                let run = source.reversed().prefix { $0 == top }.count
                let sourceIsPure = run == source.count

                for to in state.indices where to != from {
                    let target = state[to]
                    guard target.count < capacities[to] else { continue }
                    if let targetTop = target.last, targetTop != top { continue }
                    // Pouring a pure bottle into an empty one only relocates it.
                    if sourceIsPure, target.isEmpty { continue }

                    let amount = min(run, capacities[to] - target.count)
                    var next = state
                    next[from].removeLast(amount)
                    next[to].append(contentsOf: repeatElement(top, count: amount))

                    let nextKey = key(next)
                    guard seen.insert(nextKey).inserted else { continue }
                    nodes.append(Node(state: next, parent: head, move: Move(from: from, to: to)))

                    if isSolved(next) {
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
