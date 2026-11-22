import Foundation
import GameTimePersistence
import XCTest
@testable import TopOffSave

/// 1.0's `TopOffProgress`, copied verbatim (synthesized `Codable`), so tests write saves exactly as 1.0 did.
private struct OnePointZeroProgress: Codable {
    var bestMoves: [Int: Int] = [:]
    var dailyBest: [Int: Int] = [:]
    var endlessBest: [Int: Int] = [:]
    var boosterUses: [String: Int] = [:]
    var soundOn = true
    var hapticsOn = true
    var symbolsOn = false
}

final class TopOffProgressStoreTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "topoff.save.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testASaveFromOnePointZeroLoadsAndMigratesItsDays() throws {
        // Written exactly as 1.0 writes it (its own store used a plain JSONEncoder), with no dayNumbering.
        var saved = OnePointZeroProgress()
        saved.bestMoves = [1: 9, 2: 11]
        saved.dailyBest = [-736024: 14]
        saved.endlessBest = [1: 10]
        saved.boosterUses = ["hint-3": 1]
        saved.soundOn = false
        saved.symbolsOn = true
        defaults.set(try JSONEncoder().encode(saved), forKey: TopOffProgressStore.key)

        let store = TopOffProgressStore(defaults: defaults)
        let progress = store.load(dayNumberShift: 737_060)
        XCTAssertEqual(progress.bestMoves, [1: 9, 2: 11])
        XCTAssertEqual(progress.dailyBest, [1036: 14], "Japanese-calendar days move onto Gregorian numbers")
        XCTAssertEqual(progress.dayNumbering, TopOffProgress.gregorianDayNumbering)
        XCTAssertEqual(progress.boosterUses, ["hint-3": 1])
        XCTAssertFalse(progress.soundOn)
        XCTAssertTrue(progress.symbolsOn)
        XCTAssertNil(store.lastRecovery)
    }

    func testASaveMissingFieldsStillLoadsWithDefaults() {
        // A save from a build where only bestMoves and dayNumbering existed.
        defaults.set(Data(#"{"bestMoves":{"4":12},"dayNumbering":2}"#.utf8), forKey: TopOffProgressStore.key)
        let progress = TopOffProgressStore(defaults: defaults).load(dayNumberShift: 0)
        XCTAssertEqual(progress.bestMoves, [4: 12])
        XCTAssertEqual(progress.dailyBest, [:])
        XCTAssertTrue(progress.soundOn)
        XCTAssertTrue(progress.hapticsOn)
        XCTAssertFalse(progress.symbolsOn)
    }

    func testAnUnreadableSaveIsBackedUpAndSurvivesTheNextSave() throws {
        let corrupted = Data(#"{"bestMoves":"lots"}"#.utf8)
        defaults.set(corrupted, forKey: TopOffProgressStore.key)
        defaults.set(true, forKey: "colorBlindSymbols")

        let store = TopOffProgressStore(defaults: defaults)
        let progress = store.load(dayNumberShift: 0)
        XCTAssertEqual(progress.bestMoves, [:])
        XCTAssertTrue(progress.symbolsOn, "A fresh start still carries over the earliest builds' symbol toggle")
        let recovery = try XCTUnwrap(store.lastRecovery)

        var next = progress
        next.bestMoves[1] = 8
        store.save(next)

        let raw = SaveStore<TopOffProgress>(key: TopOffProgressStore.key, codec: .json, defaults: defaults) { TopOffProgress() }
        XCTAssertEqual(raw.backups(), [recovery])
        XCTAssertEqual(raw.backupData(for: recovery), corrupted)
        XCTAssertEqual(TopOffProgressStore(defaults: defaults).load(dayNumberShift: 0).bestMoves, [1: 8])
    }

    func testANewPlayerStartsFreshAndRoundTrips() {
        let store = TopOffProgressStore(defaults: defaults)
        var progress = store.load(dayNumberShift: 0)
        XCTAssertEqual(progress, TopOffProgress())
        XCTAssertNil(store.lastRecovery)
        progress.dailyBest[1036] = 15
        progress.hapticsOn = false
        store.save(progress)
        XCTAssertEqual(TopOffProgressStore(defaults: defaults).load(dayNumberShift: 999), progress,
                       "A save written by this build is already numbered, so no shift is applied")
    }
}
