import Foundation
import GameTimeCommerce

/// The two boosters a player can ask for. Both are rewarded-value placements.
public enum TopOffBooster: String, Codable, Sendable, CaseIterable {
    case hint
    case extraBottle

    /// "Extra bottle" is a continuation of a stuck attempt, so it reuses `rewardedContinue`
    /// rather than needing a new platform placement.
    public var placement: MonetizationPlacement {
        switch self {
        case .hint: .rewardedHint
        case .extraBottle: .rewardedContinue
        }
    }

    var offer: RewardOffer {
        RewardOffer(id: rawValue, kind: rawValue, amount: 1)
    }
}

public enum FreeGrantReason: String, Equatable, Sendable {
    /// The first levels teach the game and never involve ads.
    case onboarding
    /// No ad was ready (offline, no fill, SDK not started). Ad trouble never blocks play.
    case adsUnavailable
    /// Consent withheld, ads disabled, or the rewarded cooldown is running.
    case notEligible
}

public enum BoosterOutcome: Equatable, Sendable {
    /// Apply the booster. `viaAd` is true when the player earned it by watching an ad.
    case granted(viaAd: Bool, freeReason: FreeGrantReason?)
    /// The player closed the ad before earning the reward, so nothing is granted.
    case cancelled
    /// An earlier ad is still on screen.
    case busy

    public var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

public struct BoosterContext: Sendable {
    public var levelID: Int
    /// 1 for the first time this level's booster is used, then 2, and so on. It makes the reward
    /// id stable for one opportunity, so a retried grant can never pay out twice.
    public var sequence: Int
    public var isOnboarding: Bool
    public var canRequestAds: Bool

    public init(levelID: Int, sequence: Int, isOnboarding: Bool, canRequestAds: Bool) {
        self.levelID = levelID
        self.sequence = sequence
        self.isOnboarding = isOnboarding
        self.canRequestAds = canRequestAds
    }
}

/// Decides whether a booster costs an ad, and runs the ad through the shared coordinator.
///
/// Rules, from the platform monetization docs: rewarded only, nothing during the teaching
/// flow, never block play on ad failure, and only an earned reward counts.
public actor TopOffBoosterService {
    private let provider: any AdProviding
    private let coordinator: MonetizationCoordinator
    private let startedAt: Date
    private let now: @Sendable () -> Date

    public init(
        provider: any AdProviding,
        receipts: any RewardReceiptPersisting,
        tracker: any MonetizationEventTracking = NoOpMonetizationEventTracker(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.coordinator = MonetizationCoordinator(
            provider: provider,
            receipts: receipts,
            tracker: tracker,
            now: now
        )
        self.startedAt = now()
        self.now = now
    }

    /// True when watching an ad would actually be offered, so the UI only promises a video
    /// when one is ready.
    public func isAdReady(for booster: TopOffBooster, context: BoosterContext) async -> Bool {
        guard !context.isOnboarding, context.canRequestAds else { return false }
        return await provider.isAvailable(for: booster.placement)
    }

    public func request(_ booster: TopOffBooster, context: BoosterContext) async -> BoosterOutcome {
        if context.isOnboarding {
            return .granted(viaAd: false, freeReason: .onboarding)
        }

        let request = RewardRequest(
            offer: booster.offer,
            opportunity: "level-\(context.levelID).\(booster.rawValue)-\(context.sequence)"
        )
        let monetization = MonetizationContext(
            canRequestAds: context.canRequestAds,
            isOnboarding: false,
            sessionAge: now().timeIntervalSince(startedAt),
            completedLevels: 0
        )

        switch await coordinator.attempt(request, placement: booster.placement, context: monetization) {
        case .granted, .alreadyGranted:
            return .granted(viaAd: true, freeReason: nil)
        case .cancelled:
            return .cancelled
        case .busy:
            return .busy
        case .unavailable, .failed:
            return .granted(viaAd: false, freeReason: .adsUnavailable)
        case .ineligible:
            return .granted(viaAd: false, freeReason: .notEligible)
        }
    }
}
