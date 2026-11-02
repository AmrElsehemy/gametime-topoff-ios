import Foundation
import TopOffEngine

/// Everything the app remembers between launches. Local and offline; no account involved.
struct TopOffProgress: Codable, Equatable {
    /// Fewest pours used to solve each level, keyed by level id.
    var bestMoves: [Int: Int] = [:]
    /// Fewest pours used for each daily puzzle, keyed by `DailyPuzzle` day number.
    var dailyBest: [Int: Int] = [:]
    /// How the keys of `dailyBest` are numbered. Saves from 1.0 have none: their days were counted in the
    /// device's calendar and are shifted to Gregorian day numbers when loaded.
    var dayNumbering: Int? = TopOffProgress.gregorianDayNumbering
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

    static let gregorianDayNumbering = 2

    /// Consecutive days solved, ending today, or yesterday if today is still open.
    func dailyStreak(today: Int) -> Int {
        DailyPuzzle.streak(solvedDays: dailyBest.keys, today: today)
    }

    /// Moves days saved by 1.0 onto Gregorian day numbers (a no-op on Gregorian devices), so a player on
    /// another calendar keeps their daily bests and streak.
    mutating func migrateDayNumbering(shift: Int) {
        guard dayNumbering == nil else { return }
        if shift != 0 {
            dailyBest = Dictionary(dailyBest.map { ($0.key + shift, $0.value) }, uniquingKeysWith: min)
        }
        dayNumbering = Self.gregorianDayNumbering
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
            var progress = try? JSONDecoder().decode(TopOffProgress.self, from: data)
        else {
            // Carry over the symbol toggle saved by the earlier build.
            var fresh = TopOffProgress()
            fresh.symbolsOn = defaults.bool(forKey: "colorBlindSymbols")
            return fresh
        }
        progress.migrateDayNumbering(shift: DailyPuzzle.shiftFromLegacyDayNumbers())
        return progress
    }

    func save(_ progress: TopOffProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key)
    }
}
