import Foundation

/// Turns a log of events into the numbers the studio cares about: where players finish, struggle
/// and quit. Pure and deterministic, so it works on the device's own log, on a tester's exported
/// file, or on a backend's rows alike.
public struct AnalyticsSummary: Equatable, Sendable {
    public struct LevelStats: Equatable, Sendable {
        public let mode: String
        public let levelID: Int
        public var starts = 0
        public var completions = 0
        public var abandons = 0
        public var restarts = 0
        public var stuckShown = 0
        public var hintsUsed = 0
        public var totalMoves = 0
        public var totalPar = 0
        public var totalDuration = 0
        public var totalStars = 0

        public var completionRate: Double { starts == 0 ? 0 : Double(completions) / Double(starts) }
        public var abandonRate: Double { starts == 0 ? 0 : Double(abandons) / Double(starts) }
        public var averageMoves: Double { completions == 0 ? 0 : Double(totalMoves) / Double(completions) }
        /// Moves taken relative to the shortest solution. 1.0 is perfect; higher means more wandering.
        public var movesOverPar: Double { totalPar == 0 ? 0 : Double(totalMoves) / Double(totalPar) }
        public var averageSeconds: Double { completions == 0 ? 0 : Double(totalDuration) / Double(completions) }
        public var averageStars: Double { completions == 0 ? 0 : Double(totalStars) / Double(completions) }
        public var stuckRate: Double { starts == 0 ? 0 : Double(stuckShown) / Double(starts) }
    }

    public var levels: [LevelStats] = []
    public var sessions = 0
    public var installs = 0
    public var tutorialCompleted = 0
    public var campaignCompleted = 0
    public var boostersGranted = 0
    public var boostersViaAd = 0
    public var boostersCancelled = 0

    public init(events: [StoredEvent]) {
        var byLevel: [String: LevelStats] = [:]
        var order: [String] = []
        // An attempt is identified by install, level and attempt number.
        var completedAttempts: Set<String> = []
        var abandonedAttempts: [String: String] = [:]    // attempt key -> level key
        var hintsByAttempt: [String: (level: String, hints: Int)] = [:]

        func levelKey(_ p: [String: String]) -> String? {
            guard let mode = p["mode"], let id = p["level_id"].flatMap(Int.init) else { return nil }
            return "\(mode):\(id)"
        }
        func attemptKey(_ p: [String: String], level: String) -> String {
            "\(p["install_id"] ?? "?")|\(level)|\(p["attempt"] ?? "?")"
        }
        func update(_ key: String, _ p: [String: String], _ change: (inout LevelStats) -> Void) {
            if byLevel[key] == nil {
                byLevel[key] = LevelStats(mode: p["mode"] ?? "?", levelID: p["level_id"].flatMap(Int.init) ?? 0)
                order.append(key)
            }
            change(&byLevel[key]!)
        }
        func number(_ p: [String: String], _ key: String) -> Int { p[key].flatMap(Int.init) ?? 0 }

        for event in events {
            let p = event.properties
            switch event.name {
            case "first_open": installs += 1
            case "session_start": sessions += 1
            case "tutorial_completed": tutorialCompleted += 1
            case "campaign_completed": campaignCompleted += 1
            case "booster_granted":
                boostersGranted += 1
                if p["via_ad"] == "1" { boostersViaAd += 1 }
            case "booster_cancelled": boostersCancelled += 1
            case "level_started":
                if let key = levelKey(p) { update(key, p) { $0.starts += 1 } }
            case "level_completed":
                guard let key = levelKey(p) else { break }
                completedAttempts.insert(attemptKey(p, level: key))
                hintsByAttempt[attemptKey(p, level: key)] = (key, number(p, "hints"))
                update(key, p) {
                    $0.completions += 1
                    $0.totalMoves += number(p, "moves")
                    $0.totalPar += number(p, "par")
                    $0.totalDuration += number(p, "duration_s")
                    $0.totalStars += number(p, "stars")
                }
            case "level_abandoned":
                guard let key = levelKey(p) else { break }
                let attempt = attemptKey(p, level: key)
                abandonedAttempts[attempt] = key
                let previous = hintsByAttempt[attempt]?.hints ?? 0
                hintsByAttempt[attempt] = (key, max(previous, number(p, "hints")))
                update(key, p) { _ in }
            case "level_restarted":
                if let id = p["level_id"].flatMap(Int.init),
                   let key = order.last(where: { byLevel[$0]?.levelID == id }) {
                    byLevel[key]?.restarts += 1
                }
            case "stuck_shown":
                // Stuck events carry only the level id, so attach them to the matching level.
                if let id = p["level_id"].flatMap(Int.init),
                   let key = order.last(where: { byLevel[$0]?.levelID == id }) {
                    byLevel[key]?.stuckShown += 1
                }
            default: break
            }
        }

        // An attempt that was left but later finished was not abandoned.
        for (attempt, key) in abandonedAttempts where !completedAttempts.contains(attempt) {
            byLevel[key]?.abandons += 1
        }
        for (_, value) in hintsByAttempt {
            byLevel[value.level]?.hintsUsed += value.hints
        }
        levels = order.compactMap { byLevel[$0] }
    }

    /// The levels where players struggle most: the lowest completion, then the most abandons.
    public func hardestLevels(limit: Int = 5) -> [LevelStats] {
        levels.filter { $0.starts >= 1 }
            .sorted { ($0.completionRate, -Double($0.abandons)) < ($1.completionRate, -Double($1.abandons)) }
            .prefix(limit).map { $0 }
    }
}
