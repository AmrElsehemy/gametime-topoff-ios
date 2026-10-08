import Foundation

/// Everything the app remembers between launches. Local and offline; no account involved.
struct TopOffProgress: Codable, Equatable {
    /// Fewest pours used to solve each level, keyed by level id.
    var bestMoves: [Int: Int] = [:]
    var soundOn = true
    var hapticsOn = true
    var symbolsOn = false
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
