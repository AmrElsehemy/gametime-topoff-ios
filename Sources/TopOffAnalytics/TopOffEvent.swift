import Foundation
import GameTimeServices

/// Every analytics event Top Off can emit. The schema is deliberately small and fixed: adding a
/// property or an event means changing this file (and `schemaVersion`), so nothing can leak in by
/// accident. Properties are coarse gameplay facts only: no names, no emails, no device or advertising
/// identifiers, no free text.
public enum TopOffEvent: Equatable, Sendable {
    /// Bump when an event's meaning or properties change in a way analysis has to know about.
    public static let schemaVersion = 1

    public enum Mode: String, Sendable, Equatable { case campaign, daily, endless }
    /// Why a level is recorded as abandoned. `backgrounded` means the player left the app mid-level; they
    /// may well come back and finish, so analysis counts it only if that attempt is never completed.
    public enum AbandonReason: String, Sendable, Equatable {
        case leftLevel = "left_level"
        case sessionEnd = "session_end"
        case backgrounded
    }
    public enum StuckResolution: String, Sendable, Equatable { case undo, restart, bottle }

    /// Facts about a level, known when it starts.
    public struct LevelInfo: Equatable, Sendable {
        public var mode: Mode
        public var levelID: Int
        /// Campaign level number, endless level number, or the daily's weekday (0 = Monday).
        public var number: Int
        public var bottles: Int
        public var colors: Int
        public var capacity: Int
        public var hasHiddenLayers: Bool
        public var par: Int

        public init(mode: Mode, levelID: Int, number: Int, bottles: Int, colors: Int, capacity: Int, hasHiddenLayers: Bool, par: Int) {
            self.mode = mode
            self.levelID = levelID
            self.number = number
            self.bottles = bottles
            self.colors = colors
            self.capacity = capacity
            self.hasHiddenLayers = hasHiddenLayers
            self.par = par
        }
    }

    /// What happened during one attempt at a level.
    public struct RunStats: Equatable, Sendable {
        public var attempt: Int
        public var moves: Int
        public var durationSeconds: Int
        public var undos: Int
        public var restarts: Int
        public var hints: Int
        public var bottlesAdded: Int
        public var stuckSeen: Bool

        public init(attempt: Int, moves: Int, durationSeconds: Int, undos: Int, restarts: Int, hints: Int, bottlesAdded: Int, stuckSeen: Bool) {
            self.attempt = attempt
            self.moves = moves
            self.durationSeconds = durationSeconds
            self.undos = undos
            self.restarts = restarts
            self.hints = hints
            self.bottlesAdded = bottlesAdded
            self.stuckSeen = stuckSeen
        }
    }

    case firstOpen
    case sessionStart
    case sessionEnd(durationSeconds: Int, levelsCompleted: Int)
    case levelStarted(LevelInfo, attempt: Int)
    case levelCompleted(LevelInfo, RunStats, stars: Int, streak: Int?)
    case levelAbandoned(LevelInfo, RunStats, reason: AbandonReason)
    case levelRestarted(levelID: Int, movesBefore: Int)
    case undoUsed(levelID: Int, moves: Int)
    case stuckShown(levelID: Int, moves: Int)
    case stuckResolved(levelID: Int, via: StuckResolution)
    case boosterOffered(booster: String, levelID: Int)
    case boosterDeclined(booster: String, levelID: Int)
    case boosterGranted(booster: String, levelID: Int, viaAd: Bool, freeReason: String?)
    case boosterCancelled(booster: String, levelID: Int)
    case menuOpened
    case settingChanged(name: String, enabled: Bool)
    case tutorialCompleted
    case campaignCompleted(totalStars: Int)

    public var name: String {
        switch self {
        case .firstOpen: "first_open"
        case .sessionStart: "session_start"
        case .sessionEnd: "session_end"
        case .levelStarted: "level_started"
        case .levelCompleted: "level_completed"
        case .levelAbandoned: "level_abandoned"
        case .levelRestarted: "level_restarted"
        case .undoUsed: "undo_used"
        case .stuckShown: "stuck_shown"
        case .stuckResolved: "stuck_resolved"
        case .boosterOffered: "booster_offered"
        case .boosterDeclined: "booster_declined"
        case .boosterGranted: "booster_granted"
        case .boosterCancelled: "booster_cancelled"
        case .menuOpened: "menu_opened"
        case .settingChanged: "setting_changed"
        case .tutorialCompleted: "tutorial_completed"
        case .campaignCompleted: "campaign_completed"
        }
    }

    /// The event-specific properties (common fields such as session and version are added by the pipeline).
    public var properties: [String: String] {
        func level(_ info: LevelInfo) -> [String: String] {
            [
                "mode": info.mode.rawValue,
                "level_id": String(info.levelID),
                "level_number": String(info.number),
                "bottles": String(info.bottles),
                "colors": String(info.colors),
                "capacity": String(info.capacity),
                "hidden": info.hasHiddenLayers ? "1" : "0",
                "par": String(info.par)
            ]
        }
        func run(_ stats: RunStats) -> [String: String] {
            [
                "attempt": String(stats.attempt),
                "moves": String(stats.moves),
                "duration_s": String(stats.durationSeconds),
                "undos": String(stats.undos),
                "restarts": String(stats.restarts),
                "hints": String(stats.hints),
                "bottles_added": String(stats.bottlesAdded),
                "stuck_seen": stats.stuckSeen ? "1" : "0"
            ]
        }

        switch self {
        case .firstOpen, .sessionStart, .menuOpened, .tutorialCompleted:
            return [:]
        case let .sessionEnd(duration, completed):
            return ["duration_s": String(duration), "levels_completed": String(completed)]
        case let .levelStarted(info, attempt):
            return level(info).merging(["attempt": String(attempt)]) { $1 }
        case let .levelCompleted(info, stats, stars, streak):
            var p = level(info).merging(run(stats)) { $1 }
            p["stars"] = String(stars)
            if let streak { p["streak"] = String(streak) }
            return p
        case let .levelAbandoned(info, stats, reason):
            return level(info).merging(run(stats)) { $1 }.merging(["reason": reason.rawValue]) { $1 }
        case let .levelRestarted(id, moves):
            return ["level_id": String(id), "moves_before": String(moves)]
        case let .undoUsed(id, moves):
            return ["level_id": String(id), "moves": String(moves)]
        case let .stuckShown(id, moves):
            return ["level_id": String(id), "moves": String(moves)]
        case let .stuckResolved(id, via):
            return ["level_id": String(id), "via": via.rawValue]
        case let .boosterOffered(booster, id), let .boosterDeclined(booster, id), let .boosterCancelled(booster, id):
            return ["booster": booster, "level_id": String(id)]
        case let .boosterGranted(booster, id, viaAd, freeReason):
            var p = ["booster": booster, "level_id": String(id), "via_ad": viaAd ? "1" : "0"]
            if let freeReason { p["free_reason"] = freeReason }
            return p
        case let .settingChanged(name, enabled):
            return ["name": name, "enabled": enabled ? "1" : "0"]
        case let .campaignCompleted(stars):
            return ["total_stars": String(stars)]
        }
    }

    /// Every property key any event may carry, including the common ones the pipeline stamps. A test
    /// asserts nothing outside this list is ever emitted, which is the privacy guard for this schema.
    public static let allowedPropertyKeys: Set<String> = [
        // common
        "schema", "app_version", "build", "install_id", "session_id", "seq", "ts", "platform", "idiom", "os_major", "lang",
        // level
        "mode", "level_id", "level_number", "bottles", "colors", "capacity", "hidden", "par",
        // run
        "attempt", "moves", "duration_s", "undos", "restarts", "hints", "bottles_added", "stuck_seen", "stars", "streak", "reason",
        // other
        "levels_completed", "moves_before", "via", "booster", "via_ad", "free_reason", "name", "enabled", "total_stars"
    ]
}
