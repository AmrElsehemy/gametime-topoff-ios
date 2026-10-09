import Foundation
import GameTimeServices
import XCTest
@testable import TopOffAnalytics

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private final class RecordingClient: AnalyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [AnalyticsEvent] = []
    var events: [AnalyticsEvent] { lock.withLock { received } }
    func track(_ event: AnalyticsEvent) { lock.withLock { received.append(event) } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> String { lock.withLock { value += 1; return "id-\(value)" } }
}

private let context = AnalyticsPipeline.Context(appVersion: "1.0.0", build: "1", idiom: "phone", osMajor: "17", language: "en")

private func makeInfo(id: Int = 5, mode: TopOffEvent.Mode = .campaign) -> TopOffEvent.LevelInfo {
    .init(mode: mode, levelID: id, number: id, bottles: 6, colors: 4, capacity: 4, hasHiddenLayers: false, par: 12)
}

private struct Harness {
    let clock = Clock()
    let store = InMemoryEventStore()
    let client = RecordingClient()
    let suite = "topoff.analytics.tests.\(UUID().uuidString)"
    let pipeline: AnalyticsPipeline
    let gameplay: GameplayAnalytics

    init(clients: Bool = true) {
        let clock = clock
        let counter = Counter()
        pipeline = AnalyticsPipeline(
            store: store,
            clients: clients ? [client] : [],
            context: context,
            suiteName: suite,
            now: { clock.now },
            makeID: { counter.next() }
        )
        gameplay = GameplayAnalytics(pipeline: pipeline, now: { clock.now })
    }

    func events(_ name: String? = nil) -> [StoredEvent] {
        pipeline.flush()
        return store.all().filter { name == nil || $0.name == name }
    }

    func cleanUp() { UserDefaults.standard.removePersistentDomain(forName: suite) }
}

final class AnalyticsPipelineTests: XCTestCase {
    func testFirstLaunchRecordsSessionStartThenFirstOpen() {
        let h = Harness(); defer { h.cleanUp() }
        XCTAssertEqual(h.events().map(\.name), ["session_start", "first_open"])
    }

    func testEveryEventCarriesTheCommonFieldsAndASequence() {
        let h = Harness(); defer { h.cleanUp() }
        h.pipeline.track(.menuOpened)
        let events = h.events()
        let last = events.last!
        XCTAssertEqual(last.name, "menu_opened")
        for key in ["schema", "app_version", "build", "install_id", "session_id", "seq", "ts", "platform", "idiom", "os_major", "lang"] {
            XCTAssertNotNil(last.properties[key], "missing \(key)")
        }
        let sequence = events.compactMap { $0.properties["seq"].flatMap(Int.init) }
        XCTAssertEqual(sequence, Array(1...events.count), "seq increases by one per event")
        XCTAssertEqual(last.properties["schema"], "1")
    }

    func testNothingIsForwardedUnlessSharingIsOn() {
        let h = Harness(); defer { h.cleanUp() }
        h.pipeline.track(.menuOpened)
        h.pipeline.flush()
        XCTAssertTrue(h.client.events.isEmpty, "Off by default: nothing leaves the device")
        XCTAssertFalse(h.store.all().isEmpty, "...but it is still kept locally")

        h.pipeline.setSharingEnabled(true)
        h.pipeline.track(.menuOpened)
        h.pipeline.flush()
        XCTAssertEqual(h.client.events.map(\.name), ["menu_opened"])

        h.pipeline.setSharingEnabled(false)
        h.pipeline.track(.menuOpened)
        h.pipeline.flush()
        XCTAssertEqual(h.client.events.count, 1)
    }

    func testSharingChoiceAndInstallIDSurviveARelaunch() {
        let suite = "topoff.analytics.tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = AnalyticsPipeline(store: InMemoryEventStore(), context: context, suiteName: suite, makeID: { "install-A" })
        first.setSharingEnabled(true)
        first.flush()
        let storeB = InMemoryEventStore()
        let second = AnalyticsPipeline(store: storeB, context: context, suiteName: suite, makeID: { "install-B" })
        second.track(.menuOpened)
        second.flush()
        XCTAssertTrue(second.isSharingEnabled)
        XCTAssertEqual(storeB.all().last?.properties["install_id"], "install-A")
        XCTAssertFalse(storeB.all().contains { $0.name == "first_open" }, "Only the first ever launch is a first_open")
    }

    func testAShortAbsenceContinuesTheSessionAndALongOneStartsANewOne() {
        let h = Harness(); defer { h.cleanUp() }
        let firstSession = h.events("session_start").first!.properties["session_id"]
        h.gameplay.appDidEnterBackground()
        h.clock.advance(10 * 60)
        h.gameplay.appDidBecomeActive()
        h.pipeline.track(.menuOpened)
        XCTAssertEqual(h.events("session_start").count, 1, "Ten minutes away is the same session")

        h.gameplay.appDidEnterBackground()
        h.clock.advance(AnalyticsPipeline.sessionGap + 60)
        h.gameplay.appDidBecomeActive()
        h.pipeline.track(.menuOpened)
        let starts = h.events("session_start")
        XCTAssertEqual(starts.count, 2)
        XCTAssertNotEqual(starts.last!.properties["session_id"], firstSession)
        let ended = h.events("session_end")
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(ended[0].properties["session_id"], firstSession, "The old session is closed under its own id")
    }

    func testPropertiesNeverLeaveTheAllowedSchema() {
        let h = Harness(); defer { h.cleanUp() }
        let info = makeInfo()
        let stats = TopOffEvent.RunStats(attempt: 1, moves: 9, durationSeconds: 30, undos: 1, restarts: 0, hints: 1, bottlesAdded: 0, stuckSeen: true)
        let everyEvent: [TopOffEvent] = [
            .firstOpen, .sessionStart, .sessionEnd(durationSeconds: 5, levelsCompleted: 1),
            .levelStarted(info, attempt: 1), .levelCompleted(info, stats, stars: 3, streak: 4),
            .levelAbandoned(info, stats, reason: .leftLevel), .levelRestarted(levelID: 5, movesBefore: 3),
            .undoUsed(levelID: 5, moves: 3), .stuckShown(levelID: 5, moves: 9), .stuckResolved(levelID: 5, via: .undo),
            .boosterOffered(booster: "hint", levelID: 5), .boosterDeclined(booster: "hint", levelID: 5),
            .boosterGranted(booster: "hint", levelID: 5, viaAd: false, freeReason: "onboarding"),
            .boosterCancelled(booster: "hint", levelID: 5), .menuOpened,
            .settingChanged(name: "sound", enabled: false), .tutorialCompleted, .campaignCompleted(totalStars: 30)
        ]
        everyEvent.forEach(h.pipeline.track)
        for event in h.events() {
            let extra = Set(event.properties.keys).subtracting(TopOffEvent.allowedPropertyKeys)
            XCTAssertTrue(extra.isEmpty, "\(event.name) carries unexpected keys \(extra)")
        }
        XCTAssertEqual(Set(everyEvent.map(\.name)).count, everyEvent.count, "Event names are unique")
    }
}

final class GameplayAnalyticsTests: XCTestCase {
    func testASolvedLevelReportsItsRun() {
        let h = Harness(); defer { h.cleanUp() }
        h.gameplay.levelStarted(makeInfo())
        h.clock.advance(40)
        h.gameplay.movesChanged(5)
        h.gameplay.undoUsed()
        h.gameplay.hintShown()
        h.clock.advance(20)
        h.gameplay.levelSolved(moves: 14, stars: 2, streak: nil)

        let done = h.events("level_completed")
        XCTAssertEqual(done.count, 1)
        let p = done[0].properties
        XCTAssertEqual(p["moves"], "14")
        XCTAssertEqual(p["par"], "12")
        XCTAssertEqual(p["stars"], "2")
        XCTAssertEqual(p["duration_s"], "60")
        XCTAssertEqual(p["undos"], "1")
        XCTAssertEqual(p["hints"], "1")
        XCTAssertEqual(p["attempt"], "1")
        XCTAssertEqual(h.events("level_abandoned").count, 0)
    }

    func testLeavingAfterPlayingIsAnAbandonButBrowsingIsNot() {
        let h = Harness(); defer { h.cleanUp() }
        h.gameplay.levelStarted(makeInfo(id: 5))
        h.gameplay.levelStarted(makeInfo(id: 6))     // left level 5 without a pour
        XCTAssertEqual(h.events("level_abandoned").count, 0)

        h.gameplay.movesChanged(4)
        h.gameplay.levelStarted(makeInfo(id: 7))     // left level 6 after 4 moves
        let abandoned = h.events("level_abandoned")
        XCTAssertEqual(abandoned.count, 1)
        XCTAssertEqual(abandoned[0].properties["level_id"], "6")
        XCTAssertEqual(abandoned[0].properties["reason"], "left_level")

        h.gameplay.movesChanged(2)
        h.gameplay.endCurrentLevel(reason: .sessionEnd)
        XCTAssertEqual(h.events("level_abandoned").last?.properties["reason"], "session_end")
    }

    func testAttemptsCountUpPerLevel() {
        let h = Harness(); defer { h.cleanUp() }
        h.gameplay.levelStarted(makeInfo(id: 9))
        h.gameplay.levelSolved(moves: 10, stars: 3, streak: nil)
        h.gameplay.levelStarted(makeInfo(id: 9))
        h.gameplay.levelStarted(makeInfo(id: 8))
        h.gameplay.levelStarted(makeInfo(id: 9))
        let attempts = h.events("level_started").filter { $0.properties["level_id"] == "9" }.map { $0.properties["attempt"] }
        XCTAssertEqual(attempts, ["1", "2", "3"])
    }

    func testTimeInTheBackgroundDoesNotCountAsPlayTime() {
        let h = Harness(); defer { h.cleanUp() }
        h.gameplay.levelStarted(makeInfo())
        h.clock.advance(30)
        h.gameplay.appDidEnterBackground()
        h.clock.advance(600)
        h.gameplay.appDidBecomeActive()
        h.clock.advance(15)
        h.gameplay.levelSolved(moves: 12, stars: 3, streak: nil)
        XCTAssertEqual(h.events("level_completed")[0].properties["duration_s"], "45")
    }

    func testStuckIsAttributedToTheFirstThingThePlayerDoesNext() {
        let h = Harness(); defer { h.cleanUp() }
        h.gameplay.levelStarted(makeInfo())
        h.gameplay.movesChanged(8)
        h.gameplay.stuckChanged(true)
        h.gameplay.stuckChanged(true)           // a repeat does not double count
        h.gameplay.undoUsed()
        h.gameplay.undoUsed()                   // a later undo is not another resolution
        XCTAssertEqual(h.events("stuck_shown").count, 1)
        XCTAssertEqual(h.events("stuck_resolved").map { $0.properties["via"] }, ["undo"])

        h.gameplay.stuckChanged(false)
        h.gameplay.stuckChanged(true)
        h.gameplay.restarted()
        XCTAssertEqual(h.events("stuck_shown").count, 2)
        XCTAssertEqual(h.events("stuck_resolved").map { $0.properties["via"] }, ["undo", "restart"])

        h.gameplay.levelSolved(moves: 12, stars: 1, streak: nil)
        XCTAssertEqual(h.events("level_completed")[0].properties["stuck_seen"], "1")
    }

    func testNothingIsRecordedWithoutAnActiveLevel() {
        let h = Harness(); defer { h.cleanUp() }
        let before = h.events().count
        h.gameplay.undoUsed()
        h.gameplay.restarted()
        h.gameplay.stuckChanged(true)
        h.gameplay.levelSolved(moves: 1, stars: 3, streak: nil)
        XCTAssertEqual(h.events().count, before)
    }
}

final class EventStoreAndSummaryTests: XCTestCase {
    func testFileStoreRoundTripsAndTrimsToItsLimit() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("topoff-\(UUID().uuidString)/events.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileEventStore(fileURL: url, maxEvents: 20)
        for index in 0..<30 {
            store.append(StoredEvent(name: "e\(index)", properties: ["seq": String(index)]))
        }
        let kept = store.all()
        XCTAssertLessThanOrEqual(kept.count, 20)
        XCTAssertEqual(kept.last?.name, "e29", "The newest event is always kept")
        XCTAssertEqual(kept, kept.sorted { Int($0.properties["seq"]!)! < Int($1.properties["seq"]!)! }, "Order is preserved")

        store.clear()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testSummaryComputesCompletionAbandonAndStruggleNumbers() {
        let h = Harness(); defer { h.cleanUp() }
        // Level 5: two starts, one solved over par, one abandoned after being stuck.
        h.gameplay.levelStarted(makeInfo(id: 5))
        h.gameplay.stuckChanged(true)
        h.gameplay.movesChanged(6)
        h.gameplay.levelStarted(makeInfo(id: 5))          // abandons the first attempt
        h.clock.advance(50)
        h.gameplay.levelSolved(moves: 18, stars: 1, streak: nil)
        // Level 6: one clean solve.
        h.gameplay.levelStarted(makeInfo(id: 6))
        h.clock.advance(10)
        h.gameplay.levelSolved(moves: 12, stars: 3, streak: nil)

        let summary = AnalyticsSummary(events: h.events())
        let five = summary.levels.first { $0.levelID == 5 }!
        XCTAssertEqual(five.starts, 2)
        XCTAssertEqual(five.completions, 1)
        XCTAssertEqual(five.abandons, 1)
        XCTAssertEqual(five.completionRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(five.movesOverPar, 18.0 / 12.0, accuracy: 0.001)
        XCTAssertEqual(five.stuckShown, 1)
        XCTAssertEqual(five.stuckRate, 0.5, accuracy: 0.001)
        let six = summary.levels.first { $0.levelID == 6 }!
        XCTAssertEqual(six.completionRate, 1, accuracy: 0.001)
        XCTAssertEqual(six.averageStars, 3, accuracy: 0.001)
        XCTAssertEqual(summary.hardestLevels(limit: 1).first?.levelID, 5)
        XCTAssertEqual(summary.installs, 1)
        XCTAssertEqual(summary.sessions, 1)
    }

    func testSummaryCountsBoostersAndMilestones() {
        let events = [
            StoredEvent(name: "booster_granted", properties: ["via_ad": "1"]),
            StoredEvent(name: "booster_granted", properties: ["via_ad": "0", "free_reason": "ads_unavailable"]),
            StoredEvent(name: "booster_cancelled", properties: [:]),
            StoredEvent(name: "tutorial_completed", properties: [:]),
            StoredEvent(name: "campaign_completed", properties: [:])
        ]
        let summary = AnalyticsSummary(events: events)
        XCTAssertEqual(summary.boostersGranted, 2)
        XCTAssertEqual(summary.boostersViaAd, 1)
        XCTAssertEqual(summary.boostersCancelled, 1)
        XCTAssertEqual(summary.tutorialCompleted, 1)
        XCTAssertEqual(summary.campaignCompleted, 1)
    }

    func testBackgroundingMidLevelIsAbandonedOnlyIfTheAttemptIsNeverFinished() {
        let h = Harness(); defer { h.cleanUp() }
        // Attempt 1 of level 5: leave the app mid-level, come back, and finish.
        h.gameplay.levelStarted(makeInfo(id: 5))
        h.gameplay.movesChanged(6)
        h.gameplay.appDidEnterBackground()
        h.gameplay.appDidBecomeActive()
        h.gameplay.levelSolved(moves: 12, stars: 3, streak: nil)
        // Attempt 1 of level 6: leave the app mid-level and never return.
        h.gameplay.levelStarted(makeInfo(id: 6))
        h.gameplay.movesChanged(3)
        h.gameplay.appDidEnterBackground()

        XCTAssertEqual(h.events("level_abandoned").map { $0.properties["reason"] }, ["backgrounded", "backgrounded"])
        let summary = AnalyticsSummary(events: h.events())
        XCTAssertEqual(summary.levels.first { $0.levelID == 5 }?.abandons, 0, "Came back and finished: not abandoned")
        XCTAssertEqual(summary.levels.first { $0.levelID == 6 }?.abandons, 1, "Never came back: abandoned")
    }

    func testLeavingTheAppBeforeAnyMoveIsNotAnAbandon() {
        let h = Harness(); defer { h.cleanUp() }
        h.gameplay.levelStarted(makeInfo())
        h.gameplay.appDidEnterBackground()
        XCTAssertEqual(h.events("level_abandoned").count, 0)
    }
}

