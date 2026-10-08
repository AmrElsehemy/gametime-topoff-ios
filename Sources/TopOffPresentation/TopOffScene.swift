import SpriteKit
#if canImport(TopOffEngine)
import TopOffEngine
#endif
import GameTimeExperience

@MainActor
public final class TopOffScene: SKScene {
    private var game: Game
    private var selectedIndex: Int?
    private var containerNodes: [Int: SKNode] = [:]
    private let feedback: GameFeedbackController
    private var isAnimatingPour = false

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
        backgroundColor = SKColor(white: 0.07, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMove(to view: SKView) {
        renderBoard(animated: false)
    }

    public func load(level: TopOffLevel) {
        removeAllActions()
        game = Game(board: level.board)
        selectedIndex = nil
        isAnimatingPour = false
        renderBoard(animated: false)
    }

    public func undo() {
        guard !isAnimatingPour, game.undo() != nil else { return }
        feedback.play(.undo, soundEnabled: true, hapticsEnabled: true)
        selectedIndex = nil
        renderBoard(animated: true)
    }

    public func restart() {
        guard !isAnimatingPour else { return }
        game.restart()
        selectedIndex = nil
        renderBoard(animated: true)
    }

    private func handleTap(at point: CGPoint) {
        guard !isAnimatingPour else { return }

        guard let tapped = containerIndex(at: point) else {
            clearSelection()
            return
        }

        guard let selectedIndex else {
            select(tapped)
            return
        }

        if selectedIndex == tapped {
            clearSelection()
            return
        }

        do {
            let pour = try game.pour(Move(from: selectedIndex, to: tapped))
            feedback.play(.pour, soundEnabled: true, hapticsEnabled: true)
            animatePour(pour)
        } catch {
            feedback.play(.invalidMove, soundEnabled: true, hapticsEnabled: true)
            invalidFeedback(on: tapped)
        }
    }

    private func select(_ index: Int) {
        clearSelection()
        selectedIndex = index
        guard let node = containerNodes[index] else { return }
        node.run(.moveBy(x: 0, y: 14, duration: 0.12))
    }

    private func clearSelection() {
        if let selectedIndex, let node = containerNodes[selectedIndex] {
            node.run(.moveBy(x: 0, y: -14, duration: 0.12))
        }
        selectedIndex = nil
    }

    private func animatePour(_ pour: Pour) {
        guard
            let source = containerNodes[pour.move.from],
            let target = containerNodes[pour.move.to]
        else {
            selectedIndex = nil
            renderBoard(animated: true)
            finishMove()
            return
        }

        isAnimatingPour = true
        selectedIndex = nil

        let sourceOrigin = source.position
        let targetPoint = target.position
        let direction: CGFloat = targetPoint.x >= sourceOrigin.x ? 1 : -1
        let approach = CGPoint(
            x: targetPoint.x - direction * 42,
            y: targetPoint.y + 76
        )

        let stream = SKShapeNode(
            rectOf: CGSize(width: 10, height: 72),
            cornerRadius: 5
        )
        stream.fillColor = paletteColor(for: pour.color)
        stream.strokeColor = .clear
        stream.alpha = 0
        stream.position = CGPoint(
            x: targetPoint.x - direction * 8,
            y: targetPoint.y + 58
        )
        stream.zPosition = 30
        addChild(stream)

        let tilt: CGFloat = direction * -0.48
        let moveToPour = SKAction.group([
            .move(to: approach, duration: 0.18),
            .rotate(toAngle: tilt, duration: 0.18, shortestUnitArc: true)
        ])
        moveToPour.timingMode = .easeOut

        let showStream = SKAction.run {
            stream.run(.fadeIn(withDuration: 0.08))
        }

        let pourPause = SKAction.wait(forDuration: 0.26)

        let hideStream = SKAction.run {
            stream.run(.sequence([
                .fadeOut(withDuration: 0.08),
                .removeFromParent()
            ]))
        }

        let returnHome = SKAction.group([
            .move(to: sourceOrigin, duration: 0.18),
            .rotate(toAngle: 0, duration: 0.18, shortestUnitArc: true)
        ])
        returnHome.timingMode = .easeInEaseOut

        source.run(.sequence([
            moveToPour,
            showStream,
            pourPause,
            hideStream,
            returnHome,
            .run { [weak self] in
                guard let self else { return }
                self.isAnimatingPour = false
                self.renderBoard(animated: true)
                self.finishMove()
            }
        ]))
    }

    private func finishMove() {
        guard game.isSolved else { return }

        feedback.play(.solve, soundEnabled: true, hapticsEnabled: true)
        celebrate()

        run(.sequence([
            .wait(forDuration: 0.85),
            .run { [weak self] in
                self?.onSolved?()
            }
        ]))
    }

    private func invalidFeedback(on index: Int) {
        guard let node = containerNodes[index] else { return }
        node.removeAction(forKey: "invalid")
        let shake = SKAction.sequence([
            .moveBy(x: -7, y: 0, duration: 0.04),
            .moveBy(x: 14, y: 0, duration: 0.08),
            .moveBy(x: -7, y: 0, duration: 0.04)
        ])
        node.run(shake, withKey: "invalid")
    }

    private func celebrate() {
        let label = SKLabelNode(text: "Perfect")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 34
        label.alpha = 0
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.76)
        label.zPosition = 100
        addChild(label)
        label.run(.sequence([
            .group([
                .fadeIn(withDuration: 0.18),
                .scale(to: 1.12, duration: 0.18)
            ]),
            .wait(forDuration: 0.45),
            .fadeOut(withDuration: 0.18),
            .removeFromParent()
        ]))
    }

    private func renderBoard(animated: Bool) {
        removeAllChildren()
        containerNodes.removeAll()

        let containers = game.board.containers
        let count = max(containers.count, 1)
        let columns = min(count, 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let horizontalGap: CGFloat = 18
        let verticalGap: CGFloat = 34
        let bottleWidth: CGFloat = min(
            68,
            (size.width - 48 - CGFloat(columns - 1) * horizontalGap) / CGFloat(columns)
        )
        let bottleHeight: CGFloat = bottleWidth * 2.15
        let totalWidth = CGFloat(columns) * bottleWidth + CGFloat(columns - 1) * horizontalGap
        let startX = (size.width - totalWidth) / 2 + bottleWidth / 2
        let boardHeight = CGFloat(rows) * bottleHeight + CGFloat(rows - 1) * verticalGap
        let startY = size.height / 2 + boardHeight / 2 - bottleHeight / 2

        for (index, container) in containers.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = startX + CGFloat(column) * (bottleWidth + horizontalGap)
            let y = startY - CGFloat(row) * (bottleHeight + verticalGap)

            let node = makeContainerNode(
                container,
                index: index,
                size: CGSize(width: bottleWidth, height: bottleHeight)
            )
            node.position = CGPoint(x: x, y: y)

            if animated {
                node.alpha = 0
                node.setScale(0.96)
                node.run(.group([
                    .fadeIn(withDuration: 0.12),
                    .scale(to: 1, duration: 0.12)
                ]))
            }

            addChild(node)
            containerNodes[index] = node
        }
    }

    private func makeContainerNode(
        _ container: Container,
        index: Int,
        size: CGSize
    ) -> SKNode {
        let root = SKNode()
        root.name = "container-\(index)"

        let bottleRect = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
        let outline = SKShapeNode(
            rect: bottleRect,
            cornerRadius: size.width * 0.22
        )
        outline.strokeColor = SKColor(white: 0.92, alpha: 0.85)
        outline.lineWidth = 3
        outline.fillColor = SKColor(white: 1, alpha: 0.04)
        root.addChild(outline)

        let inset: CGFloat = 7
        let usableHeight = size.height - inset * 2
        let unitHeight = usableHeight / CGFloat(container.capacity)

        for (layerIndex, color) in container.layers.enumerated() {
            let layerRect = CGRect(
                x: -size.width / 2 + inset,
                y: -size.height / 2 + inset + CGFloat(layerIndex) * unitHeight,
                width: size.width - inset * 2,
                height: unitHeight - 2
            )
            let layer = SKShapeNode(rect: layerRect, cornerRadius: 6)
            layer.fillColor = paletteColor(for: color)
            layer.strokeColor = .clear
            root.addChild(layer)
        }

        return root
    }

    private func paletteColor(for color: LiquidColor) -> SKColor {
        switch color.id % 6 {
        case 1:
            return SKColor(red: 0.98, green: 0.33, blue: 0.36, alpha: 1)
        case 2:
            return SKColor(red: 0.22, green: 0.58, blue: 0.98, alpha: 1)
        case 3:
            return SKColor(red: 0.31, green: 0.82, blue: 0.55, alpha: 1)
        case 4:
            return SKColor(red: 0.96, green: 0.72, blue: 0.22, alpha: 1)
        case 5:
            return SKColor(red: 0.69, green: 0.42, blue: 0.96, alpha: 1)
        default:
            return SKColor(red: 0.98, green: 0.53, blue: 0.18, alpha: 1)
        }
    }

    private func containerIndex(at point: CGPoint) -> Int? {
        var node: SKNode? = atPoint(point)
        while let current = node {
            if
                let name = current.name,
                name.hasPrefix("container-"),
                let index = Int(name.replacingOccurrences(of: "container-", with: ""))
            {
                return index
            }
            node = current.parent
        }
        return nil
    }

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
