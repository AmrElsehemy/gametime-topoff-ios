import SpriteKit
import SwiftUI
import TopOffEngine
import TopOffPresentation
import GameTimeExperience

@main
struct TopOffApp: App {
    var body: some Scene {
        WindowGroup {
            TopOffRootView()
        }
    }
}

@MainActor
private struct TopOffRootView: View {
    @StateObject private var shell = TopOffShellModel()

    var body: some View {
        ZStack {
            // SpriteView keeps presenting its first scene unless its identity changes.
            SpriteView(scene: shell.scene)
                .id(ObjectIdentifier(shell.scene))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if shell.levelIndex == 0, shell.moves == 0, !shell.didFinishPrototype {
                    Text("Tap a bottle, then tap another to pour")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.07), in: Capsule())
                        .padding(.bottom, 30)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: shell.moves)

            if shell.showTitle {
                VStack(spacing: 6) {
                    Text("LEVEL")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(shell.levelNumber)")
                        .font(.system(size: 88, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if shell.didFinishPrototype {
                finishCard
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            controlButton(systemName: "arrow.uturn.backward", label: "Undo", enabled: shell.canUndo, action: shell.undo)

            Spacer()

            VStack(spacing: 8) {
                Text("LEVEL \(shell.levelNumber)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)

                HStack(spacing: 7) {
                    ForEach(0..<shell.levelCount, id: \.self) { index in
                        Capsule()
                            .fill(index <= shell.levelIndex ? Color.white : Color.white.opacity(0.18))
                            .frame(width: index == shell.levelIndex ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(duration: 0.35), value: shell.levelIndex)

                Text(shell.moves == 1 ? "1 move" : "\(shell.moves) moves")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: shell.moves)
            }

            Spacer()

            controlButton(systemName: "arrow.clockwise", label: "Restart", enabled: shell.moves > 0, action: shell.restart)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var finishCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.yellow)
            Text("All topped off")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text("Five levels, zero spills.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

            Button {
                shell.playAgain()
            } label: {
                Text("Play Again")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
    }

    private func controlButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.2), value: enabled)
        .accessibilityLabel(label)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

@MainActor
private final class TopOffShellModel: ObservableObject {
    @Published private(set) var scene: TopOffScene
    @Published private(set) var levelIndex = 0
    @Published private(set) var didFinishPrototype = false
    @Published private(set) var moves = 0
    @Published private(set) var canUndo = false
    @Published private(set) var showTitle = false

    private let levels = TopOffLevels.handcrafted
    private let feedback = GameFeedbackController(
        audio: TopOffAudioController(),
        haptics: TopOffHapticsController()
    )

    var levelNumber: Int { min(levelIndex + 1, levels.count) }
    var levelCount: Int { levels.count }

    init() {
        var startIndex = 0
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["TOPOFF_LEVEL"], let value = Int(raw) {
            startIndex = max(0, min(value - 1, TopOffLevels.handcrafted.count - 1))
        }
        #endif
        let first = TopOffScene(level: TopOffLevels.handcrafted[startIndex], feedback: feedback)
        scene = first
        levelIndex = startIndex
        attachHandlers(to: first)
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOPOFF_AUTOPLAY"] != nil {
            first.debugAutoplay(TopOffLevels.handcrafted[startIndex].solution)
        }
        #endif
        flashTitle()
    }

    func undo() {
        scene.undo()
    }

    func restart() {
        scene.restart()
    }

    func playAgain() {
        withAnimation(.spring(duration: 0.3)) { didFinishPrototype = false }
        levelIndex = 0
        loadCurrentLevel()
    }

    private func advance() {
        guard !didFinishPrototype else { return }

        if levelIndex + 1 >= levels.count {
            withAnimation(.spring(duration: 0.4)) { didFinishPrototype = true }
            return
        }

        levelIndex += 1
        loadCurrentLevel()
    }

    private func loadCurrentLevel() {
        let next = TopOffScene(level: levels[levelIndex], feedback: feedback)
        attachHandlers(to: next)
        moves = 0
        canUndo = false

        withAnimation(.easeInOut(duration: 0.18)) {
            scene = next
        }
        flashTitle()
    }

    private func flashTitle() {
        withAnimation(.spring(duration: 0.3)) { showTitle = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.25)) { self?.showTitle = false }
        }
    }

    private func attachHandlers(to scene: TopOffScene) {
        scene.onSolved = { [weak self] in
            self?.advance()
        }
        scene.onStateChange = { [weak self] moves, canUndo in
            self?.moves = moves
            self?.canUndo = canUndo
        }
    }
}
