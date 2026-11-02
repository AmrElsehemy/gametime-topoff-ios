import Foundation
// The pipeline, event stores and PostHog client live in GameTimeKit; re-export them so the app only
// imports TopOffAnalytics.
@_exported import GameTimeAnalytics
import GameTimeServices

public extension AnalyticsPipeline {
    /// Top Off's slug in the shared analytics project.
    static let topOffGame = "top-off"
    /// Keeps the `UserDefaults` keys the earlier, Top Off-only pipeline used, so install ids carry over.
    static let topOffKeyPrefix = "topoff.analytics"

    func track(_ event: TopOffEvent) {
        track(AnalyticsEvent(name: event.name, properties: event.properties))
    }

    /// Counts a level start and returns which attempt this is on this install, starting at 1.
    func nextAttempt(mode: TopOffEvent.Mode, levelID: Int) -> Int {
        nextAttempt(key: "\(mode.rawValue):\(levelID)")
    }
}
