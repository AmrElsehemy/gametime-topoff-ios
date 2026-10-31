#if canImport(UIKit)
import Foundation
import GameTimeAnalytics
import GameTimeServices
import UIKit

public extension AnalyticsPipeline {
    /// The pipeline the app uses: events kept in `Application Support/TopOff/events.jsonl`, stamped with
    /// coarse app and OS facts, and sent anonymously to PostHog while the player leaves sharing on (the
    /// default; Settings has the switch). A build without `PostHogAPIKey` in its Info.plist sends nothing.
    @MainActor
    static func standard() -> AnalyticsPipeline {
        let info = Bundle.main.infoDictionary ?? [:]
        let osMajor = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "?"
        let context = Context(
            game: topOffGame,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            idiom: UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
            osMajor: osMajor,
            language: Locale.current.language.languageCode?.identifier ?? "?",
            schemaVersion: TopOffEvent.schemaVersion
        )
        let clients: [any AnalyticsClient] = PostHogConfiguration(infoDictionary: info).map {
            [PostHogAnalyticsClient(configuration: $0, queueFileURL: PostHogAnalyticsClient.standardQueueURL(directory: "TopOff"))]
        } ?? []
        return AnalyticsPipeline(
            store: FileEventStore(fileURL: FileEventStore.standardURL(directory: "TopOff")),
            clients: clients,
            context: context,
            keyPrefix: topOffKeyPrefix,
            sharingByDefault: true
        )
    }
}

public enum AnalyticsEnvironment {
    /// True in debug builds and in TestFlight, where testers can export their log. App Store builds
    /// show no analytics tools to players.
    public static var isTester: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
#endif
