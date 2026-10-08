import Foundation

/// A fresh solver-verified level for every calendar day. The same day always yields the same
/// board on every device, so no backend is needed. Difficulty follows the weekday: gentle on
/// Monday, building through the week to the hardest boards on the weekend.
public enum DailyPuzzle {
    private struct Spec {
        let colors: Int
        let capacity: Int
        let empties: Int
        let visibleLayers: Int?
        let minMoves: Int
    }

    /// Indexed by `dayNumber % 7`; day 0 is Monday 1 January 2024.
    private static let weekly: [Spec] = [
        Spec(colors: 4, capacity: 3, empties: 2, visibleLayers: nil, minMoves: 8),   // Mon
        Spec(colors: 4, capacity: 4, empties: 2, visibleLayers: nil, minMoves: 12),  // Tue
        Spec(colors: 4, capacity: 4, empties: 2, visibleLayers: 2, minMoves: 10),    // Wed
        Spec(colors: 5, capacity: 4, empties: 2, visibleLayers: nil, minMoves: 15),  // Thu
        Spec(colors: 5, capacity: 4, empties: 2, visibleLayers: 2, minMoves: 14),    // Fri
        Spec(colors: 6, capacity: 4, empties: 2, visibleLayers: nil, minMoves: 19),  // Sat
        Spec(colors: 6, capacity: 4, empties: 2, visibleLayers: 2, minMoves: 18)     // Sun
    ]

    /// Whole days since 1 January 2024 in `calendar`'s time zone.
    public static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        let reference = calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_704_067_200)
        let start = calendar.startOfDay(for: reference)
        let today = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    public static func level(forDay day: Int) -> TopOffLevel {
        let spec = weekly[((day % 7) + 7) % 7]
        let base = UInt64(bitPattern: Int64(day)) &* 7919

        var fallback: (board: Board, solution: [Move])?
        for attempt in 0..<4000 {
            let board = LevelGenerator.board(
                seed: base &+ UInt64(attempt),
                colors: spec.colors,
                capacity: spec.capacity,
                empties: spec.empties,
                visibleLayers: spec.visibleLayers
            )
            guard let solution = Solver.solve(board, stateLimit: 1_500_000) else { continue }
            if solution.count >= spec.minMoves, solution.count <= spec.minMoves + 6 {
                return TopOffLevel(id: day, board: board, solution: solution)
            }
            if fallback == nil { fallback = (board, solution) }
        }
        guard let fallback else {
            preconditionFailure("No solvable daily puzzle found for day \(day)")
        }
        return TopOffLevel(id: day, board: fallback.board, solution: fallback.solution)
    }
}
