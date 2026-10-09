import Foundation
import GameTimeCommerce

/// Reward receipts that survive relaunch, so an earned reward is never paid twice. Local and
/// offline. A candidate to move into GameTimeKit once Exactly One needs the same thing.
public actor UserDefaultsRewardReceiptStore: RewardReceiptPersisting {
    private let defaults: UserDefaults
    private let key: String
    private var transactions: [String: RewardTransaction]

    /// `suiteName` selects a defaults suite (tests use their own); nil means the standard defaults.
    public init(suiteName: String? = nil, key: String = "topoff.reward-receipts.v1") {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.defaults = defaults
        self.key = key
        let stored = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([RewardTransaction].self, from: $0) } ?? []
        // Keep the earliest grant if a reward id was ever stored twice.
        self.transactions = Dictionary(
            stored.map { ($0.rewardID, $0) },
            uniquingKeysWith: { $0.grantedAt <= $1.grantedAt ? $0 : $1 }
        )
    }

    public func contains(rewardID: String) async -> Bool {
        transactions[rewardID] != nil
    }

    public func transaction(for rewardID: String) async -> RewardTransaction? {
        transactions[rewardID]
    }

    public func record(_ transaction: RewardTransaction) async throws -> Bool {
        guard transactions[transaction.rewardID] == nil else { return false }
        transactions[transaction.rewardID] = transaction
        let data = try JSONEncoder().encode(Array(transactions.values))
        defaults.set(data, forKey: key)
        return true
    }
}
