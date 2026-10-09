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

    /// Spoken name for each colour, for VoiceOver.
    static func name(for color: LiquidColor) -> String {
        switch color.id % 6 {
        case 1: return "red"
        case 2: return "blue"
        case 3: return "green"
        case 4: return "yellow"
        case 5: return "purple"
        default: return "pink"
        }
    }

    /// A distinct glyph per colour, shown when pattern mode is on so colour is never the only cue.
    static func symbol(for color: LiquidColor) -> String {
        switch color.id % 6 {
        case 1: return "⬤"
        case 2: return "▲"
        case 3: return "■"
        case 4: return "◆"
        case 5: return "★"
        default: return "✚"
        }
    }

    static let concealed = SKColor(red: 0.27, green: 0.29, blue: 0.40, alpha: 1)

    static func lighter(for color: LiquidColor) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        self.color(for: color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(
            red: r + (1 - r) * 0.45,
            green: g + (1 - g) * 0.45,
            blue: b + (1 - b) * 0.45,
            alpha: 1
        )
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
    private let surface = SKShapeNode()
    private let shading = SKSpriteNode()
    private var runNodes: [SKSpriteNode] = []
    private var shadeNodes: [SKSpriteNode] = []
    private var questionMarks: [SKLabelNode] = []
    private var symbolMarks: [SKLabelNode] = []
    private var symbolsVisible = false
    private var lastRuns: [(color: LiquidColor, concealed: Bool)] = []
    private var shownHidden = 0
    private var topRunFrame: (y: CGFloat, height: CGFloat) = (0, 0)
    private var highlighted = false
    private var completeColor: LiquidColor?
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

        // Cylindrical shading over the liquid: dark edges, bright core, so flat colour reads as volume.
        if let texture = Self.shadingTexture() {
            shading.texture = texture
            shading.size = CGSize(width: bodyWidth, height: bodyHeight)
            shading.zPosition = 8
            crop.addChild(shading)
        }

        // Thick rim so the opening reads as glass, not a line.
        let neckHalf = bodyWidth * 0.32
        let rim = SKShapeNode(
            rect: CGRect(x: -neckHalf - 3, y: bodyHeight / 2 - 5, width: neckHalf * 2 + 6, height: 7),
            cornerRadius: 3.5
        )
        rim.fillColor = SKColor(white: 1, alpha: 0.16)
        rim.strokeColor = SKColor(white: 1, alpha: 0.6)
        rim.lineWidth = 1.5
        rim.zPosition = 11
        addChild(rim)

        surface.path = CGPath(
            ellipseIn: CGRect(x: -bodyWidth * 0.5, y: -4.5, width: bodyWidth, height: 9),
            transform: nil
        )
        surface.strokeColor = .clear
        surface.zPosition = 40
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
    /// The lowest `hidden` layers are drawn as unknown. Returns true when layers were revealed
    /// since the last call, after flashing the newly exposed run.
    @discardableResult
    func setLayers(
        _ layers: [LiquidColor],
        hidden: Int = 0,
        partialTop: Int = 0,
        factor: CGFloat = 1
    ) -> Bool {
        var runs: [(color: LiquidColor, height: CGFloat, concealed: Bool)] = []
        for (index, color) in layers.enumerated() {
            let isPartial = index >= layers.count - partialTop
            let height = isPartial ? unit * factor : unit
            guard height > 0.001 else { continue }
            if index < hidden {
                runs.append((color, height, true))
            } else if let last = runs.last, !last.concealed, last.color == color {
                runs[runs.count - 1].height += height
            } else {
                runs.append((color, height, false))
            }
        }

        while runNodes.count < runs.count {
            let node = SKSpriteNode(color: .white, size: .zero)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            let shade = SKSpriteNode(texture: Self.verticalShadeTexture, color: .white, size: .zero)
            shade.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.addChild(shade)
            let mark = SKLabelNode(text: "?")
            mark.fontName = "AvenirNext-Heavy"
            mark.fontSize = unit * 0.5
            mark.fontColor = SKColor(white: 1, alpha: 0.55)
            mark.verticalAlignmentMode = .center
            mark.horizontalAlignmentMode = .center
            mark.zPosition = 2
            node.addChild(mark)
            let symbol = SKLabelNode(text: "")
            symbol.fontName = "AvenirNext-Heavy"
            symbol.fontSize = unit * 0.42
            symbol.fontColor = SKColor(white: 1, alpha: 0.8)
            symbol.verticalAlignmentMode = .center
            symbol.horizontalAlignmentMode = .center
            symbol.zPosition = 2
            node.addChild(symbol)
            liquidRoot.addChild(node)
            runNodes.append(node)
            shadeNodes.append(shade)
            questionMarks.append(mark)
            symbolMarks.append(symbol)
        }
        while runNodes.count > runs.count {
            runNodes.removeLast().removeFromParent()
            shadeNodes.removeLast()
            questionMarks.removeLast()
            symbolMarks.removeLast()
        }

        let wide = bodyHeight * 1.4
        var y = -bodyHeight / 2 + 4
        for (index, run) in runs.enumerated() {
            let node = runNodes[index]
            // The first run reaches far below so a tilted bottle never shows a gap.
            let extra: CGFloat = index == 0 ? bodyHeight * 0.6 : 0
            node.color = run.concealed ? TopOffPalette.concealed : TopOffPalette.color(for: run.color)
            questionMarks[index].isHidden = !run.concealed
            symbolMarks[index].text = TopOffPalette.symbol(for: run.color)
            // The filled circle glyph renders much larger than the others.
            symbolMarks[index].fontSize = unit * (run.color.id % 6 == 1 ? 0.3 : 0.42)
            symbolMarks[index].isHidden = run.concealed || !symbolsVisible
            symbolMarks[index].position = CGPoint(x: 0, y: extra + run.height / 2)
            questionMarks[index].position = CGPoint(x: 0, y: extra + run.height / 2)
            node.size = CGSize(width: wide, height: run.height + extra + 0.5)
            node.position = CGPoint(x: 0, y: y - extra)
            node.zPosition = CGFloat(index)
            shadeNodes[index].size = node.size
            y += run.height
        }

        surface.isHidden = runs.isEmpty
        surface.position = CGPoint(x: 0, y: y)
        if let top = runs.last {
            surface.fillColor = TopOffPalette.lighter(for: top.color)
        }
        let fill = (y + bodyHeight / 2 - 4) / (unit * CGFloat(capacity))
        shading.alpha = 0.4 + 0.6 * min(max(fill, 0), 1)

        lastRuns = runs.map { ($0.color, $0.concealed) }
        if let top = runs.last {
            topRunFrame = (y - top.height, top.height)
        }
        let revealed = hidden < shownHidden
        shownHidden = hidden
        if revealed { flashTopRun() }
        return revealed
    }

    func setSymbolsVisible(_ on: Bool) {
        symbolsVisible = on
        for (index, run) in lastRuns.enumerated() where index < symbolMarks.count {
            symbolMarks[index].isHidden = run.concealed || !on
        }
    }

    private func flashTopRun() {
        let flash = SKSpriteNode(
            color: .white,
            size: CGSize(width: bodyHeight * 1.4, height: topRunFrame.height)
        )
        flash.anchorPoint = CGPoint(x: 0.5, y: 0)
        flash.position = CGPoint(x: 0, y: topRunFrame.y)
        flash.alpha = 0.75
        flash.zPosition = 50
        liquidRoot.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    /// A small post-pour wobble of the liquid surface.
    func slosh() {
        liquidRoot.removeAction(forKey: "slosh")
        let amp: CGFloat = 0.07
        liquidRoot.run(.sequence([
            .rotate(toAngle: amp, duration: 0.10),
            .rotate(toAngle: -amp * 0.6, duration: 0.12),
            .rotate(toAngle: amp * 0.3, duration: 0.12),
            .rotate(toAngle: 0, duration: 0.10)
        ]), withKey: "slosh")
    }

    func setTilt(_ angle: CGFloat) {
        liquidRoot.removeAction(forKey: "slosh")
        zRotation = angle
        liquidRoot.zRotation = -angle
    }

    func setHighlighted(_ on: Bool) {
        highlighted = on
        updateOutline()
    }

    private func updateOutline() {
        if highlighted {
            outline.strokeColor = SKColor(white: 1, alpha: 1)
            outline.lineWidth = 3
            outline.glowWidth = 3
        } else if let completeColor {
            outline.strokeColor = TopOffPalette.lighter(for: completeColor)
            outline.lineWidth = 3
            outline.glowWidth = 4
        } else {
            outline.strokeColor = SKColor(white: 1, alpha: 0.55)
            outline.lineWidth = 2.5
            outline.glowWidth = 0
        }
    }

    func setComplete(_ on: Bool, color: LiquidColor?, animated: Bool) {
        guard on != isComplete else { return }
        isComplete = on
        completeColor = on ? color : nil
        updateOutline()
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

    private static let verticalShadeTexture: SKTexture? = {
        let space = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: 4, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let gradient = CGGradient(
                colorsSpace: space,
                colors: [
                    CGColor(red: 0, green: 0, blue: 0, alpha: 0.22),
                    CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.16)
                ] as CFArray,
                locations: [0, 0.55, 1]
            )
        else { return nil }
        // CGContext origin is bottom-left, matching SpriteKit textures.
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
        return context.makeImage().map { SKTexture(cgImage: $0) }
    }()

    private static func shadingTexture() -> SKTexture? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: 64, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let gradient = CGGradient(
                colorsSpace: space,
                colors: [
                    CGColor(red: 0, green: 0, blue: 0, alpha: 0.38),
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
                    CGColor(red: 0, green: 0, blue: 0, alpha: 0.32)
                ] as CFArray,
                locations: [0, 0.28, 0.6, 1]
            )
        else { return nil }
        context.drawLinearGradient(
            gradient, start: .zero, end: CGPoint(x: 64, y: 0), options: []
        )
        return context.makeImage().map { SKTexture(cgImage: $0) }
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
