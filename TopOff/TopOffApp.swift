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
            SpriteView(scene: shell.scene)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOP OFF")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(1.7)
                            .foregroundStyle(.white.opacity(0.68))

                        Text("Level \(shell.levelNumber) of \(shell.levelCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        controlButton(
                            systemName: "arrow.uturn.backward",
                            label: "Undo",
                            action: shell.undo
                        )

                        controlButton(
                            systemName: "arrow.clockwise",
                            label: "Restart",
                            action: shell.restart
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                if shell.didFinishPrototype {
                    VStack(spacing: 10) {
                        Text("Five levels down.")
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                        Text("The prototype loop works. Now judge the feel.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))

                        Button("Play Again") {
                            shell.playAgain()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .padding(.top, 4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.bottom, 34)
                    .padding(.horizontal, 22)
                } else {
                    Text("Tap a bottle, then tap where it should pour.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.bottom, 22)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func controlButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.3), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                }
        }
        .accessibilityLabel(label)
    }
}

@MainActor
private final class TopOffShellModel: ObservableObject {
    @Published private(set) var scene: TopOffScene
    @Published private(set) var levelIndex = 0
    @Published private(set) var didFinishPrototype = false

    private let levels = TopOffLevels.handcrafted
    private let feedback = GameFeedbackController(
        audio: TopOffAudioController(),
        haptics: TopOffHapticsController()
    )

    var levelNumber: Int { min(levelIndex + 1, levels.count) }
    var levelCount: Int { levels.count }

    init() {
        let first = TopOffScene(
            level: TopOffLevels.handcrafted[0],
            feedback: GameFeedbackController(
                audio: TopOffAudioController(),
                haptics: TopOffHapticsController()
            )
        )
        scene = first
        attachSolveHandler(to: first)
    }

    func undo() {
        scene.undo()
    }

    func restart() {
        scene.restart()
    }

    func playAgain() {
        didFinishPrototype = false
        levelIndex = 0
        loadCurrentLevel()
    }

    private func advance() {
        guard !didFinishPrototype else { return }

        if levelIndex + 1 >= levels.count {
            didFinishPrototype = true
            return
        }

        levelIndex += 1
        loadCurrentLevel()
    }

    private func loadCurrentLevel() {
        let next = TopOffScene(
            level: levels[levelIndex],
            feedback: feedback
        )
        attachSolveHandler(to: next)

        withAnimation(.easeInOut(duration: 0.18)) {
            scene = next
        }
    }

    private func attachSolveHandler(to scene: TopOffScene) {
        scene.onSolved = { [weak self] in
            self?.advance()
        }
    }
}
