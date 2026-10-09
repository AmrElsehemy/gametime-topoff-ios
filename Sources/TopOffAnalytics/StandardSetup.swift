#if canImport(UIKit)
import Foundation
import UIKit

public extension AnalyticsPipeline {
    /// The pipeline the app uses: events kept in `Application Support/TopOff/events.jsonl`, stamped with
    /// coarse app and OS facts. No clients are attached, so nothing leaves the device.
    @MainActor
    static func standard() -> AnalyticsPipeline {
        let info = Bundle.main.infoDictionary ?? [:]
        let osMajor = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "?"
        let context = Context(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            idiom: UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
            osMajor: osMajor,
            language: Locale.current.language.languageCode?.identifier ?? "?"
        )
        return AnalyticsPipeline(store: FileEventStore(fileURL: FileEventStore.standardURL()), context: context)
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
