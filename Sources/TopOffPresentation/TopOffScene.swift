import SpriteKit
#if canImport(TopOffEngine)
import TopOffEngine
#endif
import GameTimeExperience

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

    public var onSolved: (() -> Void)?

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
        activePour = nil
        buildBoard(animated: true)
    }

    public func undo() {
        guard activePour == nil, game.undo() != nil else { return }
        feedback.play(.undo, soundEnabled: true, hapticsEnabled: true)
        deselectImmediately()
        refreshBottles(animated: true)
    }

    public func restart() {
        guard activePour == nil else { return }
        game.restart()
        deselectImmediately()
        refreshBottles(animated: true)
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
                feedback.play(.invalidMove, soundEnabled: true, hapticsEnabled: true)
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
        } catch {
            feedback.play(.invalidMove, soundEnabled: true, hapticsEnabled: true)
            invalidFeedback(on: tapped)
        }
    }

    private func select(_ index: Int) {
        clearSelection()
        selectedIndex = index
        feedback.play(.placement, soundEnabled: true, hapticsEnabled: true)
        let bottle = bottles[index]
        bottle.setHighlighted(true)
        bottle.removeAction(forKey: "lift")
        let lift = SKAction.moveTo(y: homes[index].y + 20, duration: 0.14)
        lift.timingMode = .easeOut
        bottle.run(lift, withKey: "lift")
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
        let x = homes[index].x
        let shake = SKAction.sequence([
            .moveTo(x: x - 7, duration: 0.04),
            .moveTo(x: x + 7, duration: 0.08),
            .moveTo(x: x, duration: 0.04)
        ])
        bottle.run(shake, withKey: "invalid")
    }

    // MARK: - Pouring

    private func startPour(_ pour: Pour) {
        let from = pour.move.from
        let to = pour.move.to
        let source = bottles[from]
        let target = bottles[to]

        selectedIndex = nil
        source.setHighlighted(false)
        source.removeAllActions()
        source.zPosition = 50

        let direction: CGFloat = homes[to].x >= homes[from].x ? 1 : -1
        let tilt = -direction * 0.95

        // Park the lip just above the target's opening, then work out where the body must sit.
        let lipLocal = source.lip(towards: direction)
        let lipTarget = CGPoint(
            x: homes[to].x - direction * 2,
            y: homes[to].y + target.bodyHeight / 2 + 20
        )
        let rotatedLip = CGPoint(
            x: lipLocal.x * cos(tilt) - lipLocal.y * sin(tilt),
            y: lipLocal.x * sin(tilt) + lipLocal.y * cos(tilt)
        )
        let pourPose = CGPoint(x: lipTarget.x - rotatedLip.x, y: lipTarget.y - rotatedLip.y)

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
            feedback.play(.pour, soundEnabled: true, hapticsEnabled: true)
        }

        source.position = position
        source.setTilt(angle)

        // Source still holds the poured units; they drain as `progress` grows.
        let sourceLayers = game.board.containers[pour.move.from].layers
            + Array(repeating: pour.color, count: pour.amount)
        source.setLayers(sourceLayers, partialTop: pour.amount, factor: 1 - progress)

        let targetLayers = game.board.containers[pour.move.to].layers
        target.setLayers(targetLayers, partialTop: pour.amount, factor: progress)

        updateStream(animation, source: source, target: target, angle: angle, progress: progress, t: t, flow: flow)
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
        guard flowing else {
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

    private func finishPour(_ animation: PourAnimation) {
        let pour = animation.pour
        animation.stream.removeFromParent()
        activePour = nil

        let source = bottles[pour.move.from]
        source.position = homes[pour.move.from]
        source.setTilt(0)
        source.zPosition = 10
        refreshBottles(animated: true)

        if game.isSolved {
            didSolve = true
            queuedTap = nil
            feedback.play(.solve, soundEnabled: true, hapticsEnabled: true)
            celebrate()
            run(.sequence([
                .wait(forDuration: 1.25),
                .run { [weak self] in self?.onSolved?() }
            ]))
            return
        }

        if let queued = queuedTap {
            queuedTap = nil
            handleTap(onContainer: queued)
        }
    }

    // MARK: - Rendering

    private func refreshBottles(animated: Bool) {
        for (index, container) in game.board.containers.enumerated() {
            let bottle = bottles[index]
            bottle.setLayers(container.layers)
            let complete = container.isFull && container.isUniform
            bottle.setComplete(complete, color: container.topColor, animated: animated)
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
        let width = min(92, (size.width - 40 - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let tallest = CGFloat(containers.map(\.capacity).max() ?? 3) * width * 0.8 + width * 0.56
        let rowGap: CGFloat = 40
        let boardHeight = CGFloat(rows) * tallest + CGFloat(rows - 1) * rowGap
        let topY = size.height / 2 - 14 + boardHeight / 2

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
            bottle.setLayers(container.layers)
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
    }

    // MARK: - Celebration

    private func celebrate() {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0..<36 {
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
