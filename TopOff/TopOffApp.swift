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
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
                bottomBar
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
                    if shell.levelHasHiddenLayers {
                        Text("Some colours are hidden")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if let result = shell.result {
                resultBadge(result)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if shell.didFinishPrototype {
                finishCard
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $shell.showMenu) {
            TopOffMenuView(shell: shell)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Top and bottom bars

    private var topBar: some View {
        HStack(alignment: .center) {
            controlButton(systemName: "arrow.uturn.backward", label: "Undo", enabled: shell.canUndo, action: shell.undo)

            Spacer()

            Button {
                shell.showMenu = true
            } label: {
                VStack(spacing: 8) {
                    Text("LEVEL \(shell.levelNumber)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        ForEach(0..<shell.levelCount, id: \.self) { index in
                            Capsule()
                                .fill(dotColor(for: index))
                                .frame(width: index == shell.levelIndex ? 20 : 7, height: 7)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: shell.levelIndex)

                    Text(shell.moves == 1 ? "1 move" : "\(shell.moves) moves")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: shell.moves)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Level \(shell.levelNumber). Open level select")

            Spacer()

            controlButton(systemName: "arrow.clockwise", label: "Restart", enabled: shell.moves > 0, action: shell.restart)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func dotColor(for index: Int) -> Color {
        if index == shell.levelIndex { return .white }
        return shell.stars(forLevelAt: index) > 0 ? .white.opacity(0.65) : .white.opacity(0.18)
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            labelledButton(systemName: "lightbulb.fill", title: "Hint", enabled: !shell.didFinishPrototype, action: shell.hint)
            labelledButton(systemName: "plus.square.fill", title: "Bottle", enabled: shell.canAddBottle && !shell.didFinishPrototype, action: shell.addBottle)
            labelledButton(systemName: "square.grid.3x3.fill", title: "Levels", enabled: true) {
                shell.showMenu = true
            }
        }
        .padding(.bottom, 14)
    }

    // MARK: Overlays

    private func resultBadge(_ result: TopOffShellModel.Result) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(index < result.stars ? Color.yellow : Color.white.opacity(0.18))
                        .scaleEffect(index < result.stars ? 1 : 0.85)
                }
            }
            Text(result.isBest ? "New best · \(result.moves) moves" : "\(result.moves) moves")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .offset(y: -150)
    }

    private var finishCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.yellow)
            Text("All topped off")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text("\(shell.totalStars) of \(shell.levelCount * 3) stars")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

            Button {
                shell.showMenu = true
                shell.dismissFinish()
            } label: {
                Text("Pick a Level")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 6)

            Button("Play from the Start") {
                shell.playAgain()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
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

    // MARK: Buttons

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

    private func labelledButton(
        systemName: String,
        title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.2), value: enabled)
        .accessibilityLabel(title)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Level select and settings

@MainActor
private struct TopOffMenuView: View {
    @ObservedObject var shell: TopOffShellModel
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("Levels")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Spacer()
                    Label("\(shell.totalStars)", systemImage: "star.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.yellow)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<shell.levelCount, id: \.self) { index in
                        levelTile(index)
                    }
                }

                VStack(spacing: 0) {
                    toggleRow("Sound", systemName: "speaker.wave.2.fill", isOn: shell.soundBinding)
                    Divider().overlay(.white.opacity(0.1))
                    toggleRow("Haptics", systemName: "iphone.radiowaves.left.and.right", isOn: shell.hapticsBinding)
                    Divider().overlay(.white.opacity(0.1))
                    toggleRow("Colour symbols", systemName: "eye.fill", isOn: shell.symbolsBinding)
                }
                .padding(.horizontal, 16)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Colour symbols draw a shape on each colour so the puzzle never depends on colour alone.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(22)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.14).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func levelTile(_ index: Int) -> some View {
        let unlocked = shell.isUnlocked(index)
        let stars = shell.stars(forLevelAt: index)
        return Button {
            shell.play(levelAt: index)
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    Text("\(index + 1)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                        .frame(height: 29)
                }
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { star in
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(star < stars ? Color.yellow : Color.white.opacity(0.15))
                    }
                }
            }
            .foregroundStyle(unlocked ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                index == shell.levelIndex ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(index == shell.levelIndex ? .white.opacity(0.6) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!unlocked)
        .accessibilityLabel(unlocked ? "Level \(index + 1), \(stars) of 3 stars" : "Level \(index + 1), locked")
    }

    private func toggleRow(_ title: String, systemName: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Shell

@MainActor
private final class TopOffShellModel: ObservableObject {
    struct Result: Equatable {
        let stars: Int
        let moves: Int
        let isBest: Bool
    }

    @Published private(set) var scene: TopOffScene
    @Published private(set) var levelIndex = 0
    @Published private(set) var didFinishPrototype = false
    @Published private(set) var moves = 0
    @Published private(set) var canUndo = false
    @Published private(set) var canAddBottle = true
    @Published private(set) var showTitle = false
    @Published private(set) var result: Result?
    @Published private(set) var progress: TopOffProgress
    @Published var showMenu = false

    private let levels = TopOffLevels.campaign
    private let store = TopOffProgressStore()
    private let feedback = GameFeedbackController(
        audio: TopOffAudioController(),
        haptics: TopOffHapticsController()
    )

    var levelNumber: Int { min(levelIndex + 1, levels.count) }
    var levelCount: Int { levels.count }
    var levelHasHiddenLayers: Bool { levels[levelIndex].hasHiddenLayers }

    var totalStars: Int {
        levels.indices.reduce(0) { $0 + stars(forLevelAt: $1) }
    }

    init() {
        let progress = store.load()
        self.progress = progress

        var startIndex = 0
        for (index, level) in TopOffLevels.campaign.enumerated() {
            if progress.bestMoves[level.id] == nil { startIndex = index; break }
            startIndex = index
        }
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["TOPOFF_LEVEL"], let value = Int(raw) {
            startIndex = max(0, min(value - 1, TopOffLevels.campaign.count - 1))
        }
        #endif

        let first = TopOffScene(level: TopOffLevels.campaign[startIndex], feedback: feedback)
        scene = first
        levelIndex = startIndex
        apply(progress, to: first)
        attachHandlers(to: first)
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOPOFF_AUTOPLAY"] != nil {
            first.debugAutoplay(TopOffLevels.campaign[startIndex].solution)
        }
        #endif
        flashTitle()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOPOFF_MENU"] != nil { showMenu = true }
        #endif
    }

    // MARK: Progress

    func stars(forLevelAt index: Int) -> Int {
        let level = levels[index]
        guard let best = progress.bestMoves[level.id] else { return 0 }
        return level.stars(forMoves: best)
    }

    /// A level opens once every level before it has been solved.
    func isUnlocked(_ index: Int) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOPOFF_UNLOCK_ALL"] != nil { return true }
        #endif
        return levels[..<index].allSatisfy { progress.bestMoves[$0.id] != nil }
    }

    private func update(_ change: (inout TopOffProgress) -> Void) {
        var next = progress
        change(&next)
        progress = next
        store.save(next)
    }

    private func apply(_ progress: TopOffProgress, to scene: TopOffScene) {
        scene.soundEnabled = progress.soundOn
        scene.hapticsEnabled = progress.hapticsOn
        scene.showsColorSymbols = progress.symbolsOn
    }

    var soundBinding: Binding<Bool> {
        Binding(
            get: { self.progress.soundOn },
            set: { value in
                self.update { $0.soundOn = value }
                self.scene.soundEnabled = value
            }
        )
    }

    var hapticsBinding: Binding<Bool> {
        Binding(
            get: { self.progress.hapticsOn },
            set: { value in
                self.update { $0.hapticsOn = value }
                self.scene.hapticsEnabled = value
            }
        )
    }

    var symbolsBinding: Binding<Bool> {
        Binding(
            get: { self.progress.symbolsOn },
            set: { value in
                self.update { $0.symbolsOn = value }
                self.scene.showsColorSymbols = value
            }
        )
    }

    // MARK: Actions

    func undo() { scene.undo() }
    func restart() { scene.restart() }
    func hint() { scene.showHint() }
    func addBottle() { scene.addExtraBottle() }

    func play(levelAt index: Int) {
        guard isUnlocked(index) else { return }
        showMenu = false
        withAnimation(.spring(duration: 0.3)) {
            didFinishPrototype = false
            result = nil
        }
        levelIndex = index
        loadCurrentLevel()
    }

    func playAgain() {
        play(levelAt: 0)
    }

    func dismissFinish() {
        withAnimation(.spring(duration: 0.3)) { didFinishPrototype = false }
    }

    private func handleSolved(moves: Int) {
        let level = levels[levelIndex]
        let previousBest = progress.bestMoves[level.id]
        let isBest = previousBest.map { moves < $0 } ?? true
        if isBest {
            update { $0.bestMoves[level.id] = moves }
        }

        withAnimation(.spring(duration: 0.4)) {
            result = Result(stars: level.stars(forMoves: moves), moves: moves, isBest: isBest)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeIn(duration: 0.2)) { self?.result = nil }
            self?.advance()
        }
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
        apply(progress, to: next)
        attachHandlers(to: next)
        moves = 0
        canUndo = false
        canAddBottle = true

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
        scene.onSolved = { [weak self] moves in
            self?.handleSolved(moves: moves)
        }
        scene.onStateChange = { [weak self] moves, canUndo, canAddBottle in
            self?.moves = moves
            self?.canUndo = canUndo
            self?.canAddBottle = canAddBottle
        }
    }
}
