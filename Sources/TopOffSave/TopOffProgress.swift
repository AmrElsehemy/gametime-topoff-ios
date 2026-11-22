import Foundation
import GameTimePersistence
import TopOffEngine

/// Everything the app remembers between launches. Local and offline; no account involved.
public struct TopOffProgress: Codable, Equatable, Sendable {
    /// Fewest pours used to solve each level, keyed by level id.
    public var bestMoves: [Int: Int] = [:]
    /// Fewest pours used for each daily puzzle, keyed by `DailyPuzzle` day number.
    public var dailyBest: [Int: Int] = [:]
    /// How the keys of `dailyBest` are numbered. Saves from 1.0 have none: their days were counted in the
    /// device's calendar and are shifted to Gregorian day numbers when loaded.
    public var dayNumbering: Int? = TopOffProgress.gregorianDayNumbering
    /// Fewest pours used on each endless level, keyed by level number.
    public var endlessBest: [Int: Int] = [:]
    /// The furthest endless level solved.
    public var endlessReached: Int { endlessBest.keys.max() ?? 0 }
    /// How many times each booster has been granted on a level (`"hint-<levelID>"`). It gives every
    /// reward opportunity its own stable id.
    public var boosterUses: [String: Int] = [:]
    public var soundOn = true
    public var hapticsOn = true
    public var symbolsOn = false

    public static let gregorianDayNumbering = 2

    public init() {}

    /// Consecutive days solved, ending today, or yesterday if today is still open.
    public func dailyStreak(today: Int) -> Int {
        DailyPuzzle.streak(solvedDays: dailyBest.keys, today: today)
    }

    /// Moves days saved by 1.0 onto Gregorian day numbers (a no-op on Gregorian devices), so a player on
    /// another calendar keeps their daily bests and streak.
    public mutating func migrateDayNumbering(shift: Int) {
        guard dayNumbering == nil else { return }
        if shift != 0 {
            dailyBest = Dictionary(dailyBest.map { ($0.key + shift, $0.value) }, uniquingKeysWith: min)
        }
        dayNumbering = Self.gregorianDayNumbering
    }

    private enum CodingKeys: String, CodingKey {
        case bestMoves, dailyBest, dayNumbering, endlessBest, boosterUses, soundOn, hapticsOn, symbolsOn
    }

    /// Every field falls back to its default when missing, so a save written before a field existed still
    /// loads. (Synthesized decoding would reject the whole save over one missing key.) `dayNumbering` stays
    /// nil when missing: that is how a 1.0 save is recognised.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bestMoves = try container.decodeIfPresent([Int: Int].self, forKey: .bestMoves) ?? [:]
        dailyBest = try container.decodeIfPresent([Int: Int].self, forKey: .dailyBest) ?? [:]
        dayNumbering = try container.decodeIfPresent(Int.self, forKey: .dayNumbering)
        endlessBest = try container.decodeIfPresent([Int: Int].self, forKey: .endlessBest) ?? [:]
        boosterUses = try container.decodeIfPresent([String: Int].self, forKey: .boosterUses) ?? [:]
        soundOn = try container.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        hapticsOn = try container.decodeIfPresent(Bool.self, forKey: .hapticsOn) ?? true
        symbolsOn = try container.decodeIfPresent(Bool.self, forKey: .symbolsOn) ?? false
    }
}

/// Loads and saves `TopOffProgress` with GameTimeKit's `SaveStore`, under the key and JSON format the
/// game has always used. A save that cannot be read is backed up (see `lastRecovery`) instead of being
/// replaced by fresh progress on the next save.
public final class TopOffProgressStore: @unchecked Sendable {
    public static let key = "topoff.progress.v1"

    private let store: SaveStore<TopOffProgress>
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var recovery: SaveRecovery?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = SaveStore(key: Self.key, codec: .json, defaults: defaults) { TopOffProgress() }
    }

    /// - Parameter dayNumberShift: see `DailyPuzzle.shiftFromLegacyDayNumbers`; tests pass their own.
    public func load(dayNumberShift: @autoclosure () -> Int = DailyPuzzle.shiftFromLegacyDayNumbers()) -> TopOffProgress {
        switch store.load() {
        case var .loaded(progress):
            progress.migrateDayNumbering(shift: dayNumberShift())
            return progress
        case .fresh:
            return freshProgress()
        case let .recovered(_, recovery):
            lock.withLock { self.recovery = recovery }
            return freshProgress()
        }
    }

    public func save(_ progress: TopOffProgress) {
        store.save(progress)
    }

    /// Set when the last load found a save it could not read (and backed it up).
    public var lastRecovery: SaveRecovery? { lock.withLock { recovery } }

    /// A new player, carrying over the symbol toggle saved by the earliest builds.
    private func freshProgress() -> TopOffProgress {
        var fresh = TopOffProgress()
        fresh.symbolsOn = defaults.bool(forKey: "colorBlindSymbols")
        return fresh
    }
}
