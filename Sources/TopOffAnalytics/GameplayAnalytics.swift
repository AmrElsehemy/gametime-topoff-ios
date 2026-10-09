import Foundation

/// Follows the level the player is on and turns what they do into level events.
///
/// It owns the bookkeeping that is easy to get wrong: counting attempts, ending a run as
/// *abandoned* when the player leaves without finishing, not counting time spent in the
/// background, and attributing a stuck banner to the first thing the player does after seeing it.
public final class GameplayAnalytics: @unchecked Sendable {
    private struct Run {
        var info: TopOffEvent.LevelInfo
        var attempt: Int
        var moves = 0
        var undos = 0
        var restarts = 0
        var hints = 0
        var bottlesAdded = 0
        var stuckSeen = false
        var stuckOpen = false
        var activeSeconds: TimeInterval = 0
        var resumedAt: Date?
    }

    private let pipeline: AnalyticsPipeline
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var run: Run?

    public init(pipeline: AnalyticsPipeline, now: @escaping @Sendable () -> Date = { Date() }) {
        self.pipeline = pipeline
        self.now = now
    }

    // MARK: Level lifecycle

    /// A level is now on screen. Any level still in progress is recorded as abandoned first.
    public func levelStarted(_ info: TopOffEvent.LevelInfo) {
        lock.withLock {
            finishLocked(abandonedBecause: .leftLevel)
            let attempt = pipeline.nextAttempt(mode: info.mode, levelID: info.levelID)
            run = Run(info: info, attempt: attempt, resumedAt: now())
            pipeline.track(.levelStarted(info, attempt: attempt))
        }
    }

    public func levelSolved(moves: Int, stars: Int, streak: Int?) {
        lock.withLock {
            guard var current = run else { return }
            current.moves = moves
            run = current
            let stats = statsLocked()
            let info = current.info
            run = nil
            pipeline.track(.levelCompleted(info, stats, stars: stars, streak: streak))
            pipeline.noteLevelCompleted()
        }
    }

    /// Records the in-progress level as abandoned (the player went elsewhere, or the session ended).
    /// A level with no moves yet is not an abandon: the player never really started it.
    public func endCurrentLevel(reason: TopOffEvent.AbandonReason) {
        lock.withLock { finishLocked(abandonedBecause: reason) }
    }

    // MARK: Things the player does

    public func movesChanged(_ moves: Int) {
        lock.withLock { run?.moves = moves }
    }

    public func undoUsed() {
        lock.withLock {
            guard run != nil else { return }
            run?.undos += 1
            if let current = run {
                pipeline.track(.undoUsed(levelID: current.info.levelID, moves: current.moves))
            }
            resolveStuckLocked(via: .undo)
        }
    }

    public func restarted() {
        lock.withLock {
            guard let current = run else { return }
            pipeline.track(.levelRestarted(levelID: current.info.levelID, movesBefore: current.moves))
            run?.restarts += 1
            run?.moves = 0
            resolveStuckLocked(via: .restart)
        }
    }

    public func hintShown() {
        lock.withLock { run?.hints += 1 }
    }

    public func bottleAdded() {
        lock.withLock {
            run?.bottlesAdded += 1
            resolveStuckLocked(via: .bottle)
        }
    }

    public func stuckChanged(_ stuck: Bool) {
        lock.withLock {
            guard var current = run, stuck != current.stuckOpen else { return }
            current.stuckOpen = stuck
            if stuck {
                current.stuckSeen = true
                pipeline.track(.stuckShown(levelID: current.info.levelID, moves: current.moves))
            }
            run = current
        }
    }

    // MARK: Foreground and background

    /// Time in the background does not count towards how long a level took.
    public func appDidEnterBackground() {
        lock.withLock {
            guard var current = run, let resumed = current.resumedAt else { return }
            current.activeSeconds += max(0, now().timeIntervalSince(resumed))
            current.resumedAt = nil
            run = current
            // The player may never come back, and we cannot know that later, so leave a marker now.
            // Summaries count the attempt as abandoned only if it is never completed.
            let stats = statsLocked()
            if stats.moves > 0 || stats.undos > 0 || stats.restarts > 0 {
                pipeline.track(.levelAbandoned(current.info, stats, reason: .backgrounded))
            }
        }
        pipeline.appDidEnterBackground()
    }

    public func appDidBecomeActive() {
        lock.withLock {
            if run != nil, run?.resumedAt == nil { run?.resumedAt = now() }
        }
        pipeline.appDidBecomeActive()
    }

    // MARK: Locked helpers

    private func statsLocked() -> TopOffEvent.RunStats {
        guard let current = run else {
            return .init(attempt: 0, moves: 0, durationSeconds: 0, undos: 0, restarts: 0, hints: 0, bottlesAdded: 0, stuckSeen: false)
        }
        var seconds = current.activeSeconds
        if let resumed = current.resumedAt { seconds += max(0, now().timeIntervalSince(resumed)) }
        return .init(
            attempt: current.attempt,
            moves: current.moves,
            durationSeconds: Int(seconds.rounded()),
            undos: current.undos,
            restarts: current.restarts,
            hints: current.hints,
            bottlesAdded: current.bottlesAdded,
            stuckSeen: current.stuckSeen
        )
    }

    private func finishLocked(abandonedBecause reason: TopOffEvent.AbandonReason) {
        guard let current = run else { return }
        let stats = statsLocked()
        run = nil
        // Opening a level and leaving without a single pour is browsing, not abandoning.
        guard stats.moves > 0 || stats.undos > 0 || stats.restarts > 0 else { return }
        pipeline.track(.levelAbandoned(current.info, stats, reason: reason))
    }

    private func resolveStuckLocked(via resolution: TopOffEvent.StuckResolution) {
        guard var current = run, current.stuckOpen else { return }
        current.stuckOpen = false
        run = current
        pipeline.track(.stuckResolved(levelID: current.info.levelID, via: resolution))
    }
}
