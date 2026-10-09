import Foundation

/// A fresh solver-verified level for every calendar day. The same day always yields the same
/// board on every device, so no backend is needed.
///
/// Boards come from a table of seeds vetted offline by *playability* (see `DifficultyProbe`):
/// how often random tapping wins and how often a few random pours dead-end the board. Searching
/// for such boards at runtime would be far too slow on a phone, since proving a one-spare-bottle
/// board unsolvable can take hundreds of milliseconds. Each weekday has 52 seeds and the table
/// repeats yearly. Difficulty builds through the week: gentle on Monday, tense and concealed
/// towards the weekend.
public enum DailyPuzzle {
    private struct Shape {
        let colors: Int
        let capacity: Int
        let empties: Int
        let visibleLayers: Int?
    }

    /// Indexed by `dayNumber % 7`; day 0 is Monday 1 January 2024.
    private static let shapes: [Shape] = [
        Shape(colors: 3, capacity: 3, empties: 1, visibleLayers: nil), // Mon
        Shape(colors: 4, capacity: 3, empties: 1, visibleLayers: nil), // Tue
        Shape(colors: 5, capacity: 4, empties: 2, visibleLayers: 2),   // Wed
        Shape(colors: 5, capacity: 4, empties: 1, visibleLayers: 2),   // Thu
        Shape(colors: 6, capacity: 4, empties: 2, visibleLayers: 2),   // Fri
        Shape(colors: 4, capacity: 4, empties: 1, visibleLayers: nil), // Sat
        Shape(colors: 6, capacity: 4, empties: 2, visibleLayers: 1)    // Sun
    ]

    /// Vetted seeds per weekday, 52 each. Regenerate with the difficulty probes if the generator
    /// or `Shape`s ever change, because the seeds only mean something for the same generator.
    private static let seeds: [[UInt64]] = [
        [ // Mon
            2, 4, 5, 9, 12, 13, 14, 17, 20, 22, 25, 27, 29,
            31, 33, 35, 36, 38, 42, 44, 48, 49, 56, 57, 60, 61,
            64, 67, 68, 70, 73, 74, 76, 77, 78, 80, 83, 85, 86,
            87, 88, 92, 93, 94, 98, 100, 102, 104, 107, 110, 111, 114
        ],
        [ // Tue
            1, 3, 7, 22, 24, 29, 38, 41, 45, 46, 50, 53, 57,
            61, 67, 69, 75, 76, 79, 84, 86, 92, 97, 98, 99, 100,
            103, 111, 112, 113, 115, 117, 119, 126, 127, 131, 136, 137, 142,
            143, 146, 147, 150, 151, 152, 160, 161, 165, 168, 169, 171, 172
        ],
        [ // Wed
            30, 84, 91, 387, 505, 534, 583, 649, 861, 1060, 1069, 1185, 1340,
            1366, 1439, 1445, 1925, 1938, 1944, 1979, 2231, 2317, 2510, 2612, 3088, 3099,
            3330, 3334, 3380, 3606, 3779, 4077, 4695, 4795, 4880, 4997, 5176, 5183, 5195,
            5379, 5420, 5489, 5498, 5592, 5721, 5833, 5838, 5847, 5959, 6432, 6501, 6663
        ],
        [ // Thu
            18, 60, 73, 78, 102, 147, 159, 165, 200, 214, 230, 241, 248,
            279, 285, 339, 340, 401, 435, 452, 471, 478, 487, 503, 527, 537,
            564, 596, 619, 668, 677, 764, 781, 802, 822, 847, 848, 853, 873,
            875, 889, 894, 895, 952, 972, 973, 974, 1001, 1006, 1063, 1081, 1086
        ],
        [ // Fri
            28, 144, 170, 181, 267, 368, 403, 488, 530, 534, 570, 597, 603,
            619, 645, 648, 686, 695, 704, 756, 775, 867, 868, 889, 941, 983,
            1072, 1152, 1158, 1196, 1263, 1334, 1388, 1407, 1476, 1508, 1530, 1556, 1610,
            1622, 1676, 1679, 1695, 1748, 1773, 1872, 1887, 1987, 2052, 2146, 2161, 2233
        ],
        [ // Sat
            2, 5, 10, 13, 30, 63, 70, 78, 86, 112, 127, 132, 136,
            139, 150, 154, 158, 167, 170, 187, 212, 215, 219, 228, 237, 249,
            258, 272, 286, 315, 320, 329, 336, 337, 338, 339, 352, 364, 380,
            385, 391, 400, 410, 416, 417, 419, 420, 434, 443, 447, 497, 501
        ],
        [ // Sun
            14, 49, 181, 371, 403, 497, 530, 534, 597, 603, 646, 795, 868,
            889, 1072, 1117, 1152, 1158, 1263, 1405, 1407, 1456, 1476, 1508, 1556, 1605,
            1610, 1622, 1748, 1887, 1973, 1987, 2006, 2030, 2052, 2230, 2233, 2238, 2282,
            2386, 2408, 2423, 2497, 2520, 2589, 2687, 2742, 2775, 2936, 2957, 2961, 3001
        ]
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
        let weekday = ((day % 7) + 7) % 7
        return level(weekday: weekday, week: (day - weekday) / 7, id: day)
    }

    /// Builds the vetted board for a weekday shape and a week index (the table repeats yearly).
    static func level(weekday: Int, week: Int, id: Int) -> TopOffLevel {
        let table = seeds[weekday]
        let seed = table[((week % table.count) + table.count) % table.count]
        let shape = shapes[weekday]

        let board = LevelGenerator.board(
            seed: seed,
            colors: shape.colors,
            capacity: shape.capacity,
            empties: shape.empties,
            visibleLayers: shape.visibleLayers
        )
        guard let solution = Solver.solve(board, stateLimit: 1_500_000) else {
            preconditionFailure("Seed \(seed) for weekday \(weekday) is unsolvable")
        }
        return TopOffLevel(id: id, board: board, solution: solution)
    }
}

/// Endless play: one board after another, with no end. Level `n` follows the weekly rhythm of the
/// daily puzzle (gentle first, tense and concealed by the seventh) and then starts a new set of seven
/// on fresh boards. It draws on the same vetted seed table, offset by half a year so today's daily
/// puzzle does not turn up early. After 364 levels the boards repeat.
public enum EndlessPuzzle {
    /// Level ids start here so they never collide with campaign levels or daily day numbers.
    public static let idBase = 1_000_000

    public static func level(number: Int) -> TopOffLevel {
        let index = max(1, number) - 1
        return DailyPuzzle.level(weekday: index % 7, week: index / 7 + 26, id: idBase + index + 1)
    }
}
