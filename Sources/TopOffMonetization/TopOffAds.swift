#if os(iOS)
import Foundation
import GameTimeAdMob
import GameTimeCommerce

/// Owns ad setup for Top Off: consent first, then the SDK, then a provider for the booster service.
@MainActor
public final class TopOffAds {
    public let provider: AdMobRewardedProvider
    private let configuration: AdMobConfiguration
    private let consent = AdConsent()

    public private(set) var canRequestAds = false

    /// Debug builds use Google's sample ads. Release builds ship **no ad units** until real ids
    /// are set in `productionConfiguration`: the SDK is not started and every booster is free,
    /// so a release can never accidentally serve test ads.
    public static var configuration: AdMobConfiguration {
        #if DEBUG
        .testing
        #else
        productionConfiguration
        #endif
    }

    /// Fill in once the AdMob app and rewarded ad units exist. See docs/ADS.md.
    public static let productionConfiguration = AdMobConfiguration(rewardedUnitIDs: [:])

    public init(configuration: AdMobConfiguration = TopOffAds.configuration) {
        self.configuration = configuration
        self.provider = AdMobRewardedProvider(configuration: configuration)
    }

    public var isConfigured: Bool { !configuration.rewardedUnitIDs.isEmpty }

    /// Call once at launch. Does nothing when no ad units are configured.
    public func prepare() async {
        guard isConfigured else { return }
        canRequestAds = await consent.gatherConsent(testDeviceIdentifiers: configuration.testDeviceIdentifiers)
        if canRequestAds { provider.start() }
    }

    public var privacyOptionsRequired: Bool { consent.privacyOptionsRequired }

    public func presentPrivacyOptions() async {
        await consent.presentPrivacyOptions()
    }
}
#endif
