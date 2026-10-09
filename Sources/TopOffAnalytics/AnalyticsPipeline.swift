import Foundation
import GameTimeServices

/// Stamps events with the common fields, keeps them on the device, and forwards them to any
/// `AnalyticsClient` **only while sharing is enabled**. With no clients attached (the default for
/// now) nothing ever leaves the device.
///
/// Identity is a random install id made on first launch. It is not derived from the device, the
/// player or any advertising identifier, and it disappears when the app is deleted.
public final class AnalyticsPipeline: @unchecked Sendable {
    public struct Context: Sendable, Equatable {
        public var appVersion: String
        public var build: String
        public var idiom: String
        public var osMajor: String
        public var language: String

        public init(appVersion: String, build: String, idiom: String, osMajor: String, language: String) {
            self.appVersion = appVersion
            self.build = build
            self.idiom = idiom
            self.osMajor = osMajor
            self.language = language
        }
    }

    /// A gap longer than this between leaving and returning starts a new session.
    public static let sessionGap: TimeInterval = 30 * 60

    private enum Key {
        static let installID = "topoff.analytics.installID"
        static let sharing = "topoff.analytics.sharing"
        static let seq = "topoff.analytics.seq"
        static let session = "topoff.analytics.session"
        static let attempts = "topoff.analytics.attempts"
    }

    private struct SessionState: Codable {
        var id: String
        var startedAt: Date
        var lastActive: Date
        var levelsCompleted: Int
    }

    private let queue = DispatchQueue(label: "ai.knowlly.topoff.analytics", qos: .utility)
    private let store: any EventStoring
    private let clients: [any AnalyticsClient]
    private let context: Context
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    private var installID: String
    private var seq: Int
    private var session: SessionState?
    private var sharing: Bool

    /// `suiteName` picks a defaults suite (tests use their own); nil means the standard defaults.
    public init(
        store: any EventStoring,
        clients: [any AnalyticsClient] = [],
        context: Context,
        suiteName: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.store = store
        self.clients = clients
        self.context = context
        self.defaults = defaults
        self.now = now
        self.makeID = makeID
        self.installID = defaults.string(forKey: Key.installID) ?? makeID()
        self.seq = defaults.integer(forKey: Key.seq)
        self.sharing = defaults.bool(forKey: Key.sharing)
        self.session = defaults.data(forKey: Key.session).flatMap { try? JSONDecoder().decode(SessionState.self, from: $0) }
        let isFirstLaunch = defaults.string(forKey: Key.installID) == nil
        defaults.set(installID, forKey: Key.installID)
        if isFirstLaunch {
            let date = now()
            queue.async { [self] in
                ensureSession(at: date)
                emit(.firstOpen, at: date)
            }
        }
    }

    // MARK: Public API

    public var isSharingEnabled: Bool { queue.sync { sharing } }

    /// Turns forwarding to analytics clients on or off. Off by default.
    public func setSharingEnabled(_ enabled: Bool) {
        queue.sync {
            sharing = enabled
            defaults.set(enabled, forKey: Key.sharing)
        }
    }

    public func track(_ event: TopOffEvent) {
        // Read the clock now, not when the queue gets round to it: an event belongs to the moment it happened.
        let date = now()
        queue.async { [self] in
            ensureSession(at: date)
            emit(event, at: date)
        }
    }

    /// Call when the app becomes active. Starts a session, or continues the current one.
    public func appDidBecomeActive() {
        let date = now()
        queue.async { [self] in ensureSession(at: date) }
    }

    /// Call when the app goes to the background; the session is closed later if the player stays away.
    public func appDidEnterBackground() {
        let date = now()
        queue.async { [self] in
            guard var session else { return }
            session.lastActive = date
            self.session = session
            persistSession()
        }
    }

    /// Counts a level start and returns which attempt this is on this install, starting at 1.
    public func nextAttempt(mode: TopOffEvent.Mode, levelID: Int) -> Int {
        queue.sync {
            var attempts = (defaults.dictionary(forKey: Key.attempts) as? [String: Int]) ?? [:]
            let key = "\(mode.rawValue):\(levelID)"
            attempts[key, default: 0] += 1
            defaults.set(attempts, forKey: Key.attempts)
            return attempts[key] ?? 1
        }
    }

    /// Records that a level was completed in the current session, for the session summary.
    public func noteLevelCompleted() {
        queue.async { [self] in
            session?.levelsCompleted += 1
            persistSession()
        }
    }

    public func events() -> [StoredEvent] {
        queue.sync { store.all() }
    }

    /// The log file to hand to a tester's share sheet, after pending writes have landed.
    public func exportFileURL() -> URL? {
        queue.sync { store.fileURL }
    }

    public func clearLocalEvents() {
        queue.sync { store.clear() }
    }

    /// Waits for queued work. Tests use this; the app never needs to.
    public func flush() {
        queue.sync {}
    }

    // MARK: Queue-confined

    private func ensureSession(at date: Date) {
        if var current = session {
            if date.timeIntervalSince(current.lastActive) > Self.sessionGap {
                close(current, at: current.lastActive)
                start(at: date)
            } else {
                current.lastActive = date
                session = current
                persistSession()
            }
        } else {
            start(at: date)
        }
    }

    private func start(at date: Date) {
        session = SessionState(id: makeID(), startedAt: date, lastActive: date, levelsCompleted: 0)
        persistSession()
        emit(.sessionStart, at: date)
    }

    private func close(_ ended: SessionState, at date: Date) {
        let duration = max(0, Int(date.timeIntervalSince(ended.startedAt)))
        emit(.sessionEnd(durationSeconds: duration, levelsCompleted: ended.levelsCompleted), at: date, sessionID: ended.id)
    }

    private func persistSession() {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Key.session)
        }
    }

    private func emit(_ event: TopOffEvent, at date: Date, sessionID: String? = nil) {
        seq += 1
        defaults.set(seq, forKey: Key.seq)

        var properties = event.properties
        properties["schema"] = String(TopOffEvent.schemaVersion)
        properties["app_version"] = context.appVersion
        properties["build"] = context.build
        properties["install_id"] = installID
        properties["session_id"] = sessionID ?? session?.id ?? "none"
        properties["seq"] = String(seq)
        properties["ts"] = String(Int64(date.timeIntervalSince1970 * 1000))
        properties["platform"] = "ios"
        properties["idiom"] = context.idiom
        properties["os_major"] = context.osMajor
        properties["lang"] = context.language

        store.append(StoredEvent(name: event.name, properties: properties))

        guard sharing else { return }
        let outgoing = AnalyticsEvent(name: event.name, properties: properties)
        for client in clients { client.track(outgoing) }
    }
}
