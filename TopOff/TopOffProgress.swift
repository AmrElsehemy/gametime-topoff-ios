import Foundation

/// Everything the app remembers between launches. Local and offline; no account involved.
struct TopOffProgress: Codable, Equatable {
    /// Fewest pours used to solve each level, keyed by level id.
    var bestMoves: [Int: Int] = [:]
    /// Fewest pours used for each daily puzzle, keyed by `DailyPuzzle` day number.
    var dailyBest: [Int: Int] = [:]
    /// Fewest pours used on each endless level, keyed by level number.
    var endlessBest: [Int: Int] = [:]
    /// The furthest endless level solved.
    var endlessReached: Int { endlessBest.keys.max() ?? 0 }
    /// How many times each booster has been granted on a level (`"hint-<levelID>"`). It gives every
    /// reward opportunity its own stable id.
    var boosterUses: [String: Int] = [:]
    var soundOn = true
    var hapticsOn = true
    var symbolsOn = false

    /// Consecutive days solved, ending today, or yesterday if today is still open.
    func dailyStreak(today: Int) -> Int {
        var day = dailyBest[today] != nil ? today : today - 1
        var streak = 0
        while dailyBest[day] != nil {
            streak += 1
            day -= 1
        }
        return streak
    }
}

@MainActor
final class TopOffProgressStore {
    private let key = "topoff.progress.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TopOffProgress {
        guard
            let data = defaults.data(forKey: key),
            let progress = try? JSONDecoder().decode(TopOffProgress.self, from: data)
        else {
            // Carry over the symbol toggle saved by the earlier build.
            var fresh = TopOffProgress()
            fresh.symbolsOn = defaults.bool(forKey: "colorBlindSymbols")
            return fresh
        }
        return progress
    }

    func save(_ progress: TopOffProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key)
    }
}
