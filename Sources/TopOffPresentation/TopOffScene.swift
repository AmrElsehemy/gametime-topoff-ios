import SpriteKit
#if canImport(TopOffEngine)
import TopOffEngine
#endif
import GameTimeExperience

/// What VoiceOver needs to know about one bottle. `frame` is in scene coordinates (origin bottom-left).
public struct BottleAccessibility: Identifiable, Equatable, Sendable {
    public let id: Int
    public let label: String
    public let value: String
    public let frame: CGRect
}

@MainActor
public final class TopOffScene: SKScene {
    private struct PourAnimation {
        let pour: Pour
        let sourcePose: CGPoint
        let pourPose: CGPoint
        let tilt: CGFloat
        let direction: CGFloat
        let stream: SKShapeNode
        var startTime: TimeInterval?
        var didStartFlowing = false
    }

    private var game: Game
    private var selectedIndex: Int?
    private var bottles: [BottleNode] = []
    private var homes: [CGPoint] = []
    private var hitRects: [CGRect] = []
    private let feedback: GameFeedbackController
    private var activePour: PourAnimation?
    private var queuedTap: Int?
    private var didSolve = false
    private var laidOutSize: CGSize = .zero

    private let approachDuration: TimeInterval = 0.22
    private let returnDuration: TimeInterval = 0.2

    private var lastSplash: TimeInterval = 0

    /// Draws a distinct glyph on each colour so the puzzle never depends on colour alone.
    public var showsColorSymbols = false {
        didSet {
            for bottle in bottles { bottle.setSymbolsVisible(showsColorSymbols) }
        }
    }

    public var soundEnabled = true
    public var hapticsEnabled = true

    /// Called once the level is solved, with the number of pours used.
    public var onSolved: ((_ moves: Int) -> Void)?
    /// Reports move count and undo availability whenever either changes.
    public var onStateChange: ((_ moves: Int, _ canUndo: Bool, _ canAddBottle: Bool) -> Void)?
    private var extraBottleUsed = false

    /// Fires when the board proves unsolvable (the player is stuck) and again when that clears.
    public var onStuckChange: ((Bool) -> Void)?
    /// Fires whenever bottle contents or selection change, so VoiceOver can describe the board.
    public var onAccessibilityChange: (([BottleAccessibility]) -> Void)?
    private var isStuck = false
    private var analysisGeneration = 0

    private var reduceMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    #if DEBUG
    private var autoplayMoves: [Move] = []
    private var nextAutoplay: TimeInterval?

    /// Debug only: plays the reference solution so animations can be inspected without touch input.
    public func debugAutoplay(_ moves: [Move]) {
        autoplayMoves = moves
        nextAutoplay = nil
    }

    /// Debug only: plays random legal pours, to reach dead ends and exercise the stuck banner.
    public func debugRandomPlay() {
        debugRandom = true
        nextAutoplay = nil
    }
    private var debugRandom = false
    #endif

    private func notifyState() {
        onStateChange?(game.moveCount, game.canUndo, !extraBottleUsed && !didSolve)
    }

    public init(
        level: TopOffLevel = TopOffLevels.handcrafted[0],
        size: CGSize = CGSize(width: 390, height: 844),
        feedback: GameFeedbackController = GameFeedbackController(
            audio: NoOpAudioController(),
            haptics: NoOpHapticsController()
        )
    ) {
        self.game = Game(board: level.board)
        self.feedback = feedback
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMove(to view: SKView) {
        buildBoard(animated: true)
        analyzeBoard()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard view != nil, activePour == nil, size != laidOutSize else { return }
        buildBoard(animated: false)
    }

    public func load(level: TopOffLevel) {
        removeAllActions()
        game = Game(board: level.board)
        selectedIndex = nil
        queuedTap = nil
        didSolve = false
        extraBottleUsed = false
        activePour = nil
        buildBoard(animated: true)
        notifyState()
        analyzeBoard()
    }

    public func undo() {
        guard activePour == nil, game.undo() != nil else { return }
        feedback.play(.undo, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        deselectImmediately()
        refreshBottles(animated: true)
        notifyState()
        analyzeBoard()
    }

    public func restart() {
        guard activePour == nil else { return }
        let hadExtra = extraBottleUsed
        game.restart()
        extraBottleUsed = false
        deselectImmediately()
        if hadExtra {
            buildBoard(animated: false)
        } else {
            refreshBottles(animated: true)
        }
        notifyState()
        analyzeBoard()
    }

    // MARK: - Input

    private func handleTap(at point: CGPoint) {
        let tapped = hitRects.firstIndex { $0.contains(point) }
        handleTap(onContainer: tapped)
    }

    private func handleTap(onContainer tapped: Int?) {
        guard !didSolve else { return }

        // Taps during a pour are remembered so quick play never feels dropped.
        if activePour != nil {
            if let tapped { queuedTap = tapped }
            return
        }

        guard let tapped else {
            clearSelection()
            return
        }

        guard let from = selectedIndex else {
            guard !game.board.containers[tapped].isEmpty else {
                invalidFeedback(on: tapped)
                feedback.play(.invalidMove, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
                return
            }
            select(tapped)
            return
        }

        if from == tapped {
            clearSelection()
            return
        }

        do {
            let pour = try game.pour(Move(from: from, to: tapped))
            startPour(pour)
            notifyState()
        } catch {
            feedback.play(.invalidMove, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
            invalidFeedback(on: tapped)
        }
    }

    private func select(_ index: Int) {
        clearSelection()
        selectedIndex = index
        feedback.play(.placement, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        let bottle = bottles[index]
        bottle.setHighlighted(true)
        bottle.removeAction(forKey: "lift")
        // With Reduce Motion on, the glow alone marks the selection.
        if !reduceMotion {
            let lift = SKAction.moveTo(y: homes[index].y + 20, duration: 0.14)
            lift.timingMode = .easeOut
            bottle.run(lift, withKey: "lift")
        }
        announce("Bottle \(index + 1) selected")
        notifyAccessibility()
    }

    private func clearSelection() {
        guard let index = selectedIndex else { return }
        selectedIndex = nil
        let bottle = bottles[index]
        bottle.setHighlighted(false)
        bottle.removeAction(forKey: "lift")
        let drop = SKAction.moveTo(y: homes[index].y, duration: 0.12)
        drop.timingMode = .easeIn
        bottle.run(drop, withKey: "lift")
        notifyAccessibility()
    }

    private func deselectImmediately() {
        guard let index = selectedIndex else { return }
        selectedIndex = nil
        bottles[index].setHighlighted(false)
        bottles[index].removeAction(forKey: "lift")
        bottles[index].position = homes[index]
    }

    private func invalidFeedback(on index: Int) {
        let bottle = bottles[index]
        bottle.removeAction(forKey: "invalid")
        announce("Can't pour there")
        if reduceMotion {
            // No shake: flash the outline instead.
            bottle.run(.sequence([
                .run { bottle.setHighlighted(true) },
                .wait(forDuration: 0.25),
                .run { bottle.setHighlighted(false) }
            ]), withKey: "invalid")
            return
        }
        let x = homes[index].x
        let shake = SKAction.sequence([
            .moveTo(x: x - 7, duration: 0.04),
            .moveTo(x: x + 7, duration: 0.08),
            .moveTo(x: x, duration: 0.04)
        ])
        bottle.run(shake, withKey: "invalid")
    }

    // MARK: - Stuck detection

    /// Re-checks, off the main thread, whether the board can still be solved. Only a complete search
    /// that finds no solution counts as stuck; running out of search budget says nothing.
    private func analyzeBoard() {
        analysisGeneration += 1
        let generation = analysisGeneration
        guard !didSolve else {
            setStuck(false)
            return
        }
        let board = game.board
        Task.detached(priority: .utility) { [weak self] in
            let result = Solver.analyze(board, stateLimit: 300_000)
            await MainActor.run {
                guard let self, self.analysisGeneration == generation else { return }
                self.setStuck(result == .unsolvable)
            }
        }
    }

    private func setStuck(_ stuck: Bool) {
        guard stuck != isStuck else { return }
        isStuck = stuck
        onStuckChange?(stuck)
        if stuck {
            announce("This board can't be finished. Undo a few moves or restart.")
        }
    }

    /// Plays the "no" cue for a hint that cannot work, so the tap is never met with silence.
    public func rejectHint() {
        feedback.play(.invalidMove, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        if !isStuck {
            announce("No hint available right now.")
        }
    }

    // MARK: - Accessibility

    /// Activates a bottle exactly as a tap would, for VoiceOver users.
    public func activateBottle(_ index: Int) {
        guard bottles.indices.contains(index) else { return }
        handleTap(onContainer: index)
    }

    private func describe(_ container: Container, index: Int) -> (label: String, value: String) {
        let position = "Bottle \(index + 1) of \(bottles.count)"
        if container.isEmpty { return (position + ", empty", selectedIndex == index ? "Selected" : "") }

        let hidden = container.isFull && container.isUniform ? 0 : container.hiddenLayers
        var parts: [String] = []
        var unknown = 0
        // Read from the top down, merging runs of one colour.
        for (offset, color) in container.layers.reversed().enumerated() {
            let layerIndex = container.layers.count - 1 - offset
            if layerIndex < hidden { unknown += 1; continue }
            let name = TopOffPalette.name(for: color)
            if let last = parts.last, last.hasPrefix(name + " ") {
                let count = (Int(last.dropFirst(name.count + 1)) ?? 1) + 1
                parts[parts.count - 1] = "\(name) \(count)"
            } else {
                parts.append("\(name) 1")
            }
        }
        var text = parts.joined(separator: ", then ")
        if unknown > 0 {
            text += (text.isEmpty ? "" : ", then ") + "\(unknown) unknown"
        }
        let complete = container.isFull && container.isUniform
        let label = position + (complete ? ", complete" : "") + ". From the top: " + text
        return (label, selectedIndex == index ? "Selected" : "")
    }

    private func notifyAccessibility() {
        guard let onAccessibilityChange else { return }
        let items = game.board.containers.enumerated().map { index, container -> BottleAccessibility in
            let description = describe(container, index: index)
            return BottleAccessibility(
                id: index,
                label: description.label,
                value: description.value,
                frame: index < hitRects.count ? hitRects[index] : .zero
            )
        }
        onAccessibilityChange(items)
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    // MARK: - Boosters

    /// Whether a hint can be shown right now, so the player is never asked to earn one that cannot work.
    public var hintAvailable: Bool {
        activePour == nil && !didSolve && Solver.solve(game.board, stateLimit: 400_000) != nil
    }

    /// Highlights the next move of a shortest solution from the current position.
    /// Returns false if there is nothing to suggest (solved, mid-pour, or no solution from here).
    @discardableResult
    public func showHint() -> Bool {
        guard activePour == nil, !didSolve else { return false }
        guard let move = Solver.solve(game.board, stateLimit: 400_000)?.first else { return false }

        clearSelection()
        feedback.play(.hint, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        let source = bottles[move.from]
        let target = bottles[move.to]
        source.setHighlighted(true)
        target.setHighlighted(true)
        announce("Hint: pour bottle \(move.from + 1) into bottle \(move.to + 1)")

        for bottle in [source, target] {
            bottle.removeAction(forKey: "hint")
            bottle.run(.sequence([
                .scale(to: 1.06, duration: 0.18),
                .scale(to: 1, duration: 0.18),
                .scale(to: 1.06, duration: 0.18),
                .scale(to: 1, duration: 0.18),
                .wait(forDuration: 0.8),
                .run { bottle.setHighlighted(false) }
            ]), withKey: "hint")
        }
        return true
    }

    /// Adds one spare empty bottle for this attempt. Returns false if already used.
    @discardableResult
    public func addExtraBottle() -> Bool {
        guard activePour == nil, !didSolve, !extraBottleUsed else { return false }
        extraBottleUsed = true
        game.addExtraContainer()
        deselectImmediately()
        buildBoard(animated: false)
        // Pop the new bottle in so the change is obvious.
        if let bottle = bottles.last {
            bottle.alpha = 0
            if reduceMotion {
                bottle.run(.fadeIn(withDuration: 0.2))
            } else {
                bottle.setScale(0.2)
                bottle.run(.group([
                    .fadeIn(withDuration: 0.15),
                    .scale(to: 1, duration: 0.25)
                ]))
            }
        }
        feedback.play(.placement, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        announce("Extra bottle added")
        notifyState()
        analyzeBoard()
        return true
    }

    // MARK: - Pouring

    private func startPour(_ pour: Pour) {
        let from = pour.move.from
        let to = pour.move.to
        let source = bottles[from]
        let target = bottles[to]

        selectedIndex = nil
        analysisGeneration += 1
        setStuck(false)
        source.setHighlighted(false)
        source.removeAllActions()
        source.zPosition = 50

        let direction: CGFloat = homes[to].x >= homes[from].x ? 1 : -1

        // Park the lip just above the target's opening, then work out where the body must sit.
        // The steeper the tilt, the further the body swings away from the target, so ease the
        // tilt until the whole bottle stays on screen (bottles at the edge pouring inward).
        let lipLocal = source.lip(towards: direction)
        let lipTarget = CGPoint(
            x: homes[to].x - direction * 2,
            y: homes[to].y + target.bodyHeight / 2 + 20
        )
        let margin: CGFloat = 6
        var tilt = -direction * 0.8
        var pourPose = CGPoint.zero
        for magnitude in stride(from: CGFloat(0.8), through: 0.35, by: -0.05) {
            tilt = -direction * magnitude
            let rotatedLip = CGPoint(
                x: lipLocal.x * cos(tilt) - lipLocal.y * sin(tilt),
                y: lipLocal.x * sin(tilt) + lipLocal.y * cos(tilt)
            )
            pourPose = CGPoint(x: lipTarget.x - rotatedLip.x, y: lipTarget.y - rotatedLip.y)

            let corners = [
                CGPoint(x: -source.bodyWidth / 2, y: -source.bodyHeight / 2),
                CGPoint(x: source.bodyWidth / 2, y: -source.bodyHeight / 2),
                CGPoint(x: -source.bodyWidth / 2, y: source.bodyHeight / 2),
                CGPoint(x: source.bodyWidth / 2, y: source.bodyHeight / 2)
            ]
            let xs = corners.map { pourPose.x + $0.x * cos(tilt) - $0.y * sin(tilt) }
            if let minX = xs.min(), let maxX = xs.max(),
               minX >= margin, maxX <= size.width - margin {
                break
            }
        }

        let stream = SKShapeNode()
        stream.strokeColor = TopOffPalette.color(for: pour.color)
        stream.lineWidth = 7
        stream.lineCap = .round
        stream.zPosition = 45
        stream.alpha = 0
        addChild(stream)

        activePour = PourAnimation(
            pour: pour,
            sourcePose: source.position,
            pourPose: pourPose,
            tilt: tilt,
            direction: direction,
            stream: stream
        )
    }

    private func pourDuration(for pour: Pour) -> TimeInterval {
        0.34 + 0.16 * Double(pour.amount)
    }

    public override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        if debugRandom, activePour == nil, selectedIndex == nil, !didSolve, !isStuck {
            if let due = nextAutoplay {
                if currentTime >= due {
                    let board = game.board
                    var legal: [Move] = []
                    for from in board.containers.indices {
                        for to in board.containers.indices where from != to {
                            if (try? board.validate(Move(from: from, to: to))) != nil { legal.append(Move(from: from, to: to)) }
                        }
                    }
                    if let move = legal.randomElement() {
                        handleTap(onContainer: move.from)
                        run(.sequence([
                            .wait(forDuration: 0.3),
                            .run { [weak self] in self?.handleTap(onContainer: move.to) }
                        ]))
                    }
                    nextAutoplay = currentTime + 1.8
                }
            } else {
                nextAutoplay = currentTime + 1.0
            }
        }
        if activePour == nil, selectedIndex == nil, !didSolve, !autoplayMoves.isEmpty {
            if let due = nextAutoplay {
                if currentTime >= due {
                    let move = autoplayMoves.removeFirst()
                    handleTap(onContainer: move.from)
                    run(.sequence([
                        .wait(forDuration: 0.35),
                        .run { [weak self] in self?.handleTap(onContainer: move.to) }
                    ]))
                    nextAutoplay = currentTime + 2.2
                }
            } else {
                nextAutoplay = currentTime + 1.2
            }
        }
        #endif

        guard var animation = activePour else { return }
        if animation.startTime == nil { animation.startTime = currentTime }
        let t = currentTime - (animation.startTime ?? currentTime)

        let pour = animation.pour
        let source = bottles[pour.move.from]
        let target = bottles[pour.move.to]
        let flow = pourDuration(for: pour)
        let total = approachDuration + flow + returnDuration

        if t >= total {
            finishPour(animation)
            return
        }

        let home = homes[pour.move.from]
        var position = home
        var angle: CGFloat = 0
        var progress: CGFloat = 0

        if t < approachDuration {
            let k = Self.easeOut(CGFloat(t / approachDuration))
            position = Self.lerp(animation.sourcePose, animation.pourPose, k)
            angle = animation.tilt * k
        } else if t < approachDuration + flow {
            position = animation.pourPose
            angle = animation.tilt
            progress = Self.easeInOut(CGFloat((t - approachDuration) / flow))
        } else {
            let k = Self.easeInOut(CGFloat((t - approachDuration - flow) / returnDuration))
            position = Self.lerp(animation.pourPose, home, k)
            angle = animation.tilt * (1 - k)
            progress = 1
        }

        if progress > 0, !animation.didStartFlowing {
            animation.didStartFlowing = true
            feedback.play(.pour, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        }

        if reduceMotion {
            // The liquid still drains and fills, but nothing swings across the screen.
            position = home
            angle = 0
        }
        source.position = position
        source.setTilt(angle)

        // Source still holds the poured units; they drain as `progress` grows.
        let sourceLayers = game.board.containers[pour.move.from].layers
            + Array(repeating: pour.color, count: pour.amount)
        source.setLayers(
            sourceLayers,
            hidden: pour.sourceHiddenBefore,
            partialTop: pour.amount,
            factor: 1 - progress
        )

        let targetContainer = game.board.containers[pour.move.to]
        target.setLayers(
            targetContainer.layers,
            hidden: displayedHidden(targetContainer),
            partialTop: pour.amount,
            factor: progress
        )

        updateStream(animation, source: source, target: target, angle: angle, progress: progress, t: t, flow: flow)
        if progress > 0.02, progress < 0.98, currentTime - lastSplash > 0.05, !reduceMotion {
            lastSplash = currentTime
            spawnSplash(animation, target: target, progress: progress)
        }
        activePour = animation
    }

    private func updateStream(
        _ animation: PourAnimation,
        source: BottleNode,
        target: BottleNode,
        angle: CGFloat,
        progress: CGFloat,
        t: TimeInterval,
        flow: TimeInterval
    ) {
        let flowing = t >= approachDuration - 0.02 && t <= approachDuration + flow + 0.04
        guard flowing, !reduceMotion else {
            animation.stream.alpha = 0
            return
        }

        let lipLocal = source.lip(towards: animation.direction)
        let lip = CGPoint(
            x: source.position.x + lipLocal.x * cos(angle) - lipLocal.y * sin(angle),
            y: source.position.y + lipLocal.x * sin(angle) + lipLocal.y * cos(angle)
        )
        let targetUnits = CGFloat(game.board.containers[animation.pour.move.to].layers.count - animation.pour.amount)
            + CGFloat(animation.pour.amount) * progress
        let surfaceY = homes[animation.pour.move.to].y - target.bodyHeight / 2 + 4 + targetUnits * target.unit

        let path = CGMutablePath()
        path.move(to: lip)
        path.addLine(to: CGPoint(x: lip.x, y: surfaceY))
        animation.stream.path = path
        animation.stream.alpha = 1
    }

    private func spawnSplash(_ animation: PourAnimation, target: BottleNode, progress: CGFloat) {
        let container = game.board.containers[animation.pour.move.to]
        let units = CGFloat(container.layers.count - animation.pour.amount)
            + CGFloat(animation.pour.amount) * progress
        let home = homes[animation.pour.move.to]
        let surfaceY = home.y - target.bodyHeight / 2 + 4 + units * target.unit

        for _ in 0..<2 {
            let radius = CGFloat.random(in: 1.8...3.6)
            let drop = SKShapeNode(circleOfRadius: radius)
            drop.fillColor = TopOffPalette.lighter(for: animation.pour.color)
            drop.strokeColor = .clear
            drop.position = CGPoint(x: home.x + CGFloat.random(in: -6...6), y: surfaceY + 3)
            drop.zPosition = 46
            addChild(drop)
            let rise = SKAction.moveBy(
                x: CGFloat.random(in: -16...16),
                y: CGFloat.random(in: 12...26),
                duration: 0.18
            )
            rise.timingMode = .easeOut
            let fall = SKAction.moveBy(x: 0, y: -14, duration: 0.14)
            fall.timingMode = .easeIn
            drop.run(.sequence([
                rise,
                .group([fall, .fadeOut(withDuration: 0.14)]),
                .removeFromParent()
            ]))
        }
    }

    private func finishPour(_ animation: PourAnimation) {
        let pour = animation.pour
        animation.stream.removeFromParent()
        activePour = nil

        let source = bottles[pour.move.from]
        source.position = homes[pour.move.from]
        source.setTilt(0)
        source.zPosition = 10
        refreshBottles(animated: true)
        if !reduceMotion {
            source.slosh()
            bottles[pour.move.to].slosh()
        }
        announce("Poured \(TopOffPalette.name(for: pour.color)) from bottle \(pour.move.from + 1) into bottle \(pour.move.to + 1)")

        if game.isSolved {
            didSolve = true
            queuedTap = nil
            feedback.play(.solve, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
            announce("Level solved in \(game.moveCount) moves")
            celebrate()
            run(.sequence([
                .wait(forDuration: 1.25),
                .run { [weak self] in
                    guard let self else { return }
                    self.onSolved?(self.game.moveCount)
                }
            ]))
            return
        }

        analyzeBoard()

        if let queued = queuedTap {
            queuedTap = nil
            handleTap(onContainer: queued)
        }
    }

    // MARK: - Rendering

    /// A finished bottle shows its true colours even if it started with concealed layers.
    private func displayedHidden(_ container: Container) -> Int {
        container.isFull && container.isUniform ? 0 : container.hiddenLayers
    }

    private func refreshBottles(animated: Bool) {
        var revealed = false
        var completedNow = false
        for (index, container) in game.board.containers.enumerated() {
            let bottle = bottles[index]
            if bottle.setLayers(container.layers, hidden: displayedHidden(container)), animated {
                revealed = true
            }
            let complete = container.isFull && container.isUniform
            if complete, !bottle.isComplete { completedNow = true }
            bottle.setComplete(complete, color: container.topColor, animated: animated && !reduceMotion)
        }
        notifyAccessibility()
        guard animated, activePour == nil else { return }
        // A solve has its own fanfare, so the smaller cues only play mid-level.
        if completedNow, !game.isSolved {
            feedback.play(.milestone, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        } else if revealed {
            feedback.play(.hint, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
        }
    }

    private func buildBoard(animated: Bool) {
        removeAllChildren()
        bottles.removeAll()
        homes.removeAll()
        hitRects.removeAll()
        laidOutSize = size

        addBackground()

        let containers = game.board.containers
        let count = max(containers.count, 1)
        let columns = count <= 4 ? count : Int(ceil(Double(count) / 2))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let gap: CGFloat = 16
        let rowGap: CGFloat = 40
        let maxCapacity = CGFloat(containers.map(\.capacity).max() ?? 3)
        // Keep the board clear of the HUD above and the home indicator below, shrinking bottles
        // on tall boards instead of letting them run underneath the controls.
        let topInset: CGFloat = 175
        let bottomInset: CGFloat = 135
        let availableHeight = size.height - topInset - bottomInset
        let heightPerWidth = maxCapacity * 0.8 + 0.56
        let widthForHeight = (availableHeight - CGFloat(rows - 1) * rowGap) / (CGFloat(rows) * heightPerWidth)
        let widthForColumns = (size.width - 40 - CGFloat(columns - 1) * gap) / CGFloat(columns)
        // Phones cap bottles at 92pt; wider screens such as iPad get proportionally larger ones.
        let maxBottleWidth: CGFloat = size.width > 600 ? 130 : 92
        let width = min(maxBottleWidth, widthForColumns, widthForHeight)
        let tallest = heightPerWidth * width
        let boardHeight = CGFloat(rows) * tallest + CGFloat(rows - 1) * rowGap
        let topY = size.height - topInset - (availableHeight - boardHeight) / 2

        for (index, container) in containers.enumerated() {
            let row = index / columns
            let column = index % columns
            let rowCount = min(columns, count - row * columns)
            let rowWidth = CGFloat(rowCount) * width + CGFloat(rowCount - 1) * gap
            let x = (size.width - rowWidth) / 2 + width / 2 + CGFloat(column) * (width + gap)
            // Bottles sit on a shared floor per row.
            let bottle = BottleNode(capacity: container.capacity, width: width)
            let floorY = topY - CGFloat(row) * (tallest + rowGap) - tallest
            let y = floorY + bottle.bodyHeight / 2
            let home = CGPoint(x: x, y: y)

            bottle.position = home
            bottle.zPosition = 10
            bottle.setLayers(container.layers, hidden: displayedHidden(container))
            bottle.setSymbolsVisible(showsColorSymbols)
            bottle.setComplete(
                container.isFull && container.isUniform,
                color: container.topColor,
                animated: false
            )
            addChild(bottle)
            addChild(makeShadow(under: home, bottle: bottle))
            if column == 0 { addShelf(row: row, y: home.y - bottle.bodyHeight / 2 - 8) }

            bottles.append(bottle)
            homes.append(home)
            hitRects.append(CGRect(
                x: x - width / 2 - gap / 2,
                y: y - bottle.bodyHeight / 2 - 10,
                width: width + gap,
                height: bottle.bodyHeight + 30
            ))

            if animated {
                bottle.alpha = 0
                if reduceMotion {
                    bottle.run(.fadeIn(withDuration: 0.2))
                } else {
                    bottle.position.y -= 24
                    bottle.run(.sequence([
                        .wait(forDuration: 0.05 * Double(index)),
                        .group([
                            .fadeIn(withDuration: 0.18),
                            .moveTo(y: y, duration: 0.22)
                        ])
                    ]))
                }
            }
        }
        notifyAccessibility()
    }

    private func addShelf(row: Int, y: CGFloat) {
        let shelf = SKShapeNode(
            rect: CGRect(x: 20, y: y - 3, width: size.width - 40, height: 6),
            cornerRadius: 3
        )
        shelf.fillColor = SKColor(white: 1, alpha: 0.07)
        shelf.strokeColor = .clear
        shelf.zPosition = 0
        addChild(shelf)
    }

    private func makeShadow(under home: CGPoint, bottle: BottleNode) -> SKNode {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: bottle.bodyWidth * 0.95, height: 14))
        shadow.fillColor = SKColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: home.x, y: home.y - bottle.bodyHeight / 2 - 2)
        shadow.zPosition = 1
        return shadow
    }

    private func addBackground() {
        let space = CGColorSpaceCreateDeviceRGB()
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let gradient = CGGradient(
                colorsSpace: space,
                colors: [
                    CGColor(red: 0.13, green: 0.12, blue: 0.27, alpha: 1),
                    CGColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1)
                ] as CFArray,
                locations: [0, 1]
            )
        else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.55),
            startRadius: 0,
            endCenter: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.55),
            endRadius: CGFloat(height) * 0.7,
            options: [.drawsAfterEndLocation]
        )
        guard let image = context.makeImage() else { return }
        let background = SKSpriteNode(texture: SKTexture(cgImage: image), size: size)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.zPosition = -10
        addChild(background)
        addBokeh()
    }

    /// Soft drifting lights behind the board; positions are deterministic so relayout never flickers.
    private func addBokeh() {
        for index in 0..<14 {
            let seed = CGFloat(index)
            let radius = 14 + 26 * abs(sin(seed * 12.9898))
            let orb = SKShapeNode(circleOfRadius: radius)
            orb.fillColor = TopOffPalette.color(for: LiquidColor(index % 6 + 1))
            orb.strokeColor = .clear
            orb.alpha = 0.035 + 0.04 * abs(sin(seed * 4.1))
            orb.position = CGPoint(
                x: size.width * abs(sin(seed * 78.233)),
                y: size.height * abs(sin(seed * 37.719))
            )
            orb.zPosition = -9
            addChild(orb)
            // Reduce Motion keeps the lights but holds them still.
            if reduceMotion { continue }
            let drift = 14 + 18 * abs(sin(seed * 9.1))
            let period = 5 + 4 * abs(sin(seed * 2.3))
            let up = SKAction.moveBy(x: 0, y: drift, duration: period)
            up.timingMode = .easeInEaseOut
            orb.run(.repeatForever(.sequence([up, up.reversed()])))
        }
    }

    // MARK: - Celebration

    private func celebrate() {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0..<(reduceMotion ? 0 : 36) {
            let piece = SKShapeNode(rectOf: CGSize(width: 8, height: 12), cornerRadius: 2)
            piece.fillColor = TopOffPalette.color(for: LiquidColor(index % 6 + 1))
            piece.strokeColor = .clear
            piece.position = center
            piece.zPosition = 90
            piece.zRotation = CGFloat.random(in: 0...(.pi))
            addChild(piece)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 90...260)
            let burst = SKAction.group([
                .moveBy(
                    x: cos(angle) * distance,
                    y: sin(angle) * distance + 40,
                    duration: 0.55
                ),
                .rotate(byAngle: CGFloat.random(in: -6...6), duration: 0.9)
            ])
            burst.timingMode = .easeOut
            piece.run(.sequence([
                burst,
                .group([
                    .moveBy(x: 0, y: -160, duration: 0.5),
                    .fadeOut(withDuration: 0.5)
                ]),
                .removeFromParent()
            ]))
        }

        let label = SKLabelNode(text: "Perfect")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 38
        label.alpha = 0
        label.setScale(0.6)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.80)
        label.zPosition = 100
        addChild(label)
        label.run(.sequence([
            .group([
                .fadeIn(withDuration: 0.16),
                .scale(to: 1.1, duration: 0.2)
            ]),
            .wait(forDuration: 0.6),
            .fadeOut(withDuration: 0.25),
            .removeFromParent()
        ]))
    }

    // MARK: - Math

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    private static func easeOut(_ x: CGFloat) -> CGFloat {
        1 - (1 - x) * (1 - x)
    }

    private static func easeInOut(_ x: CGFloat) -> CGFloat {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    // MARK: - Touch

    #if os(iOS)
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        handleTap(at: point)
    }
    #elseif os(macOS)
    public override func mouseUp(with event: NSEvent) {
        handleTap(at: event.location(in: self))
    }
    #endif
}
