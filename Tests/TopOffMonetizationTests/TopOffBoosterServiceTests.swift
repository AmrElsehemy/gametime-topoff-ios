import GameTimeCommerce
import XCTest
@testable import TopOffMonetization

private final class FakeAds: AdProviding, @unchecked Sendable {
    var available = true
    var result: AdPresentationResult = .completed
    private(set) var presentCount = 0

    func isAvailable(for placement: MonetizationPlacement) async -> Bool { available }

    func present(_ placement: MonetizationPlacement) async throws -> AdPresentationResult {
        presentCount += 1
        return result
    }
}

private func context(
    sequence: Int = 1,
    onboarding: Bool = false,
    canRequestAds: Bool = true
) -> BoosterContext {
    BoosterContext(levelID: 5, sequence: sequence, isOnboarding: onboarding, canRequestAds: canRequestAds)
}

final class TopOffBoosterServiceTests: XCTestCase {
    private func service(_ ads: FakeAds) -> TopOffBoosterService {
        TopOffBoosterService(provider: ads, receipts: InMemoryRewardReceiptStore())
    }

    func testOnboardingBoostersAreFreeAndNeverTouchAds() async {
        let ads = FakeAds()
        let outcome = await service(ads).request(.hint, context: context(onboarding: true))
        XCTAssertEqual(outcome, .granted(viaAd: false, freeReason: .onboarding))
        XCTAssertEqual(ads.presentCount, 0)
    }

    func testEarnedAdGrantsTheBooster() async {
        let ads = FakeAds()
        let outcome = await service(ads).request(.hint, context: context())
        XCTAssertEqual(outcome, .granted(viaAd: true, freeReason: nil))
        XCTAssertEqual(ads.presentCount, 1)
    }

    func testClosingTheAdEarlyGrantsNothing() async {
        let ads = FakeAds()
        ads.result = .cancelled
        let outcome = await service(ads).request(.extraBottle, context: context())
        XCTAssertEqual(outcome, .cancelled)
    }

    func testMissingAdNeverBlocksPlay() async {
        let ads = FakeAds()
        ads.available = false
        let outcome = await service(ads).request(.hint, context: context())
        XCTAssertEqual(outcome, .granted(viaAd: false, freeReason: .adsUnavailable))
        XCTAssertEqual(ads.presentCount, 0)
    }

    func testWithheldConsentGivesAFreeBoosterAndShowsNoAd() async {
        let ads = FakeAds()
        let outcome = await service(ads).request(.hint, context: context(canRequestAds: false))
        XCTAssertEqual(outcome, .granted(viaAd: false, freeReason: .notEligible))
        XCTAssertEqual(ads.presentCount, 0)
    }

    func testAdIsOnlyOfferedWhenOneIsReady() async {
        let ads = FakeAds()
        let service = service(ads)
        var ready = await service.isAdReady(for: .hint, context: context())
        XCTAssertTrue(ready)
        ads.available = false
        ready = await service.isAdReady(for: .hint, context: context())
        XCTAssertFalse(ready)
        ads.available = true
        ready = await service.isAdReady(for: .hint, context: context(onboarding: true))
        XCTAssertFalse(ready, "Never promise a video during the teaching flow")
    }

    func testSameOpportunityNeverShowsASecondAd() async {
        let ads = FakeAds()
        let store = InMemoryRewardReceiptStore()
        let service = TopOffBoosterService(provider: ads, receipts: store)
        _ = await service.request(.hint, context: context(sequence: 1))
        let again = await service.request(.hint, context: context(sequence: 1))
        // The shared policy's 30s rewarded cooldown applies first, so a rapid replay resolves as a
        // free grant. Either way the player is never shown a second ad for one opportunity.
        XCTAssertTrue(again.isGranted)
        XCTAssertEqual(ads.presentCount, 1)
    }

    func testReceiptsPersistAcrossInstances() async throws {
        let suite = "topoff.tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let transaction = RewardTransaction(rewardID: "r1", offerID: "hint", grantedAt: Date())
        let first = UserDefaultsRewardReceiptStore(suiteName: suite, key: "k")
        let recorded = try await first.record(transaction)
        XCTAssertTrue(recorded)
        let duplicate = try await first.record(transaction)
        XCTAssertFalse(duplicate)

        let second = UserDefaultsRewardReceiptStore(suiteName: suite, key: "k")
        let restored = await second.contains(rewardID: "r1")
        XCTAssertTrue(restored)
    }
}
