import SpriteKit
#if canImport(TopOffEngine)
import TopOffEngine
#endif

enum TopOffPalette {
    static func color(for color: LiquidColor) -> SKColor {
        switch color.id % 6 {
        case 1: return SKColor(red: 0.99, green: 0.36, blue: 0.40, alpha: 1)
        case 2: return SKColor(red: 0.25, green: 0.62, blue: 1.00, alpha: 1)
        case 3: return SKColor(red: 0.30, green: 0.85, blue: 0.58, alpha: 1)
        case 4: return SKColor(red: 1.00, green: 0.76, blue: 0.25, alpha: 1)
        case 5: return SKColor(red: 0.70, green: 0.45, blue: 0.98, alpha: 1)
        default: return SKColor(red: 1.00, green: 0.52, blue: 0.76, alpha: 1)
        }
    }

    static func darker(for color: LiquidColor) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        self.color(for: color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r * 0.62, green: g * 0.62, blue: b * 0.62, alpha: 1)
    }
}

/// A glass bottle that draws its own liquid. Liquid stays level while the bottle tilts.
@MainActor
final class BottleNode: SKNode {
    let capacity: Int
    let bodyWidth: CGFloat
    let unit: CGFloat
    let bodyHeight: CGFloat

    private let liquidRoot = SKNode()
    private let outline = SKShapeNode()
    private let surface = SKSpriteNode(color: SKColor(white: 1, alpha: 0.35), size: .zero)
    private var runNodes: [SKSpriteNode] = []
    private var cap: SKShapeNode?
    private(set) var isComplete = false

    /// Local position of the lip, on the side the bottle pours toward.
    func lip(towards direction: CGFloat) -> CGPoint {
        CGPoint(x: direction * bodyWidth * 0.3, y: bodyHeight / 2)
    }

    init(capacity: Int, width: CGFloat) {
        self.capacity = capacity
        self.bodyWidth = width
        self.unit = width * 0.8
        self.bodyHeight = CGFloat(capacity) * width * 0.8 + width * 0.8 * 0.7
        super.init()

        let path = Self.bottlePath(width: bodyWidth, height: bodyHeight)

        let glass = SKShapeNode(path: path)
        glass.fillColor = SKColor(white: 1, alpha: 0.06)
        glass.strokeColor = .clear
        addChild(glass)

        let mask = SKShapeNode(path: path)
        mask.fillColor = .white
        mask.strokeColor = .clear
        let crop = SKCropNode()
        crop.maskNode = mask
        crop.addChild(liquidRoot)
        addChild(crop)

        surface.zPosition = 5
        liquidRoot.addChild(surface)

        outline.path = path
        outline.fillColor = .clear
        outline.strokeColor = SKColor(white: 1, alpha: 0.55)
        outline.lineWidth = 2.5
        outline.lineJoin = .round
        outline.zPosition = 10
        addChild(outline)

        let shine = SKShapeNode(
            rect: CGRect(
                x: -bodyWidth / 2 + 8,
                y: -bodyHeight / 2 + 18,
                width: 5,
                height: bodyHeight * 0.5
            ),
            cornerRadius: 2.5
        )
        shine.fillColor = SKColor(white: 1, alpha: 0.2)
        shine.strokeColor = .clear
        shine.zPosition = 11
        addChild(shine)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Draws `layers` bottom to top. The last `partialTop` layers are scaled by `factor`,
    /// which is how a pour drains one bottle and fills another.
    func setLayers(_ layers: [LiquidColor], partialTop: Int = 0, factor: CGFloat = 1) {
        var runs: [(color: LiquidColor, height: CGFloat)] = []
        for (index, color) in layers.enumerated() {
            let isPartial = index >= layers.count - partialTop
            let height = isPartial ? unit * factor : unit
            guard height > 0.001 else { continue }
            if let last = runs.last, last.color == color {
                runs[runs.count - 1].height += height
            } else {
                runs.append((color, height))
            }
        }

        while runNodes.count < runs.count {
            let node = SKSpriteNode(color: .white, size: .zero)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            liquidRoot.addChild(node)
            runNodes.append(node)
        }
        while runNodes.count > runs.count {
            runNodes.removeLast().removeFromParent()
        }

        let wide = bodyHeight * 1.4
        var y = -bodyHeight / 2 + 4
        for (index, run) in runs.enumerated() {
            let node = runNodes[index]
            node.color = TopOffPalette.color(for: run.color)
            // The first run reaches far below so a tilted bottle never shows a gap.
            let extra: CGFloat = index == 0 ? bodyHeight * 0.6 : 0
            node.size = CGSize(width: wide, height: run.height + extra + 0.5)
            node.position = CGPoint(x: 0, y: y - extra)
            node.zPosition = CGFloat(index)
            y += run.height
        }

        surface.isHidden = runs.isEmpty
        surface.size = CGSize(width: wide, height: 3)
        surface.position = CGPoint(x: 0, y: y - 3)
        surface.anchorPoint = CGPoint(x: 0.5, y: 0)
    }

    func setTilt(_ angle: CGFloat) {
        zRotation = angle
        liquidRoot.zRotation = -angle
    }

    func setHighlighted(_ on: Bool) {
        outline.strokeColor = SKColor(white: 1, alpha: on ? 1 : 0.55)
        outline.lineWidth = on ? 3.5 : 2.5
    }

    func setComplete(_ on: Bool, color: LiquidColor?, animated: Bool) {
        guard on != isComplete else { return }
        isComplete = on
        cap?.removeFromParent()
        cap = nil
        guard on, let color else { return }

        let neckWidth = bodyWidth * 0.64
        let node = SKShapeNode(
            rect: CGRect(x: -neckWidth / 2 - 3, y: 0, width: neckWidth + 6, height: 13),
            cornerRadius: 5
        )
        node.fillColor = TopOffPalette.darker(for: color)
        node.strokeColor = SKColor(white: 1, alpha: 0.5)
        node.lineWidth = 1.5
        node.position = CGPoint(x: 0, y: bodyHeight / 2 - 5)
        node.zPosition = 12
        addChild(node)
        cap = node

        if animated {
            node.setScale(0.1)
            node.alpha = 0
            node.position.y += 22
            let drop = SKAction.group([
                .fadeIn(withDuration: 0.1),
                .scale(to: 1, duration: 0.16),
                .moveBy(x: 0, y: -22, duration: 0.16)
            ])
            drop.timingMode = .easeIn
            node.run(drop)
            run(.sequence([
                .scale(to: 1.08, duration: 0.09),
                .scale(to: 1, duration: 0.14)
            ]))
        }
    }

    private static func bottlePath(width w: CGFloat, height h: CGFloat) -> CGPath {
        let r = w * 0.32
        let neckHalf = w * 0.32
        let neckH = w * 0.24
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w / 2, y: -h / 2 + r))
        path.addArc(
            tangent1End: CGPoint(x: -w / 2, y: -h / 2),
            tangent2End: CGPoint(x: -w / 2 + r, y: -h / 2),
            radius: r
        )
        path.addLine(to: CGPoint(x: w / 2 - r, y: -h / 2))
        path.addArc(
            tangent1End: CGPoint(x: w / 2, y: -h / 2),
            tangent2End: CGPoint(x: w / 2, y: -h / 2 + r),
            radius: r
        )
        path.addLine(to: CGPoint(x: w / 2, y: h / 2 - neckH * 1.7))
        path.addQuadCurve(
            to: CGPoint(x: neckHalf, y: h / 2 - neckH * 0.7),
            control: CGPoint(x: w / 2, y: h / 2 - neckH * 0.8)
        )
        path.addLine(to: CGPoint(x: neckHalf, y: h / 2))
        path.addLine(to: CGPoint(x: -neckHalf, y: h / 2))
        path.addLine(to: CGPoint(x: -neckHalf, y: h / 2 - neckH * 0.7))
        path.addQuadCurve(
            to: CGPoint(x: -w / 2, y: h / 2 - neckH * 1.7),
            control: CGPoint(x: -w / 2, y: h / 2 - neckH * 0.8)
        )
        path.closeSubpath()
        return path
    }
}
