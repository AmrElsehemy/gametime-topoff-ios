import SpriteKit
import OSLog
import SwiftUI
import TopOffEngine
import TopOffMonetization
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pop-in transitions become plain fades when the player has Reduce Motion on.
    private func pop(_ scale: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: scale).combined(with: .opacity)
    }

    var body: some View {
        ZStack {
            // SpriteView keeps presenting its first scene unless its identity changes.
            SpriteView(scene: shell.scene)
                .id(ObjectIdentifier(shell.scene))
                .ignoresSafeArea()

            boardAccessibility

            VStack(spacing: 0) {
                topBar
                Spacer()
                if shell.isStuck, !shell.didFinishPrototype {
                    stuckBanner
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if shell.levelIndex == 0, !shell.isDaily, shell.moves == 0, !shell.didFinishPrototype {
                    Text("Tap a bottle, then tap another to pour")
                        .scaledFont(14, .semibold)
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
                    Text(shell.isDaily ? "TODAY'S" : (shell.isEndless ? "ENDLESS" : "LEVEL"))
                        .scaledFont(15, .heavy)
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(shell.isDaily ? "Daily" : "\(shell.endlessNumber ?? shell.levelNumber)")
                        .scaledFont(88, .black)
                        .foregroundStyle(.white)
                    if shell.levelHasHiddenLayers {
                        Text("Some colours are hidden")
                            .scaledFont(14, .semibold)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                .transition(pop(0.85))
                .allowsHitTesting(false)
            }

            if let result = shell.result {
                resultBadge(result)
                    .transition(pop(0.8))
                    .allowsHitTesting(false)
            }

            if shell.didFinishPrototype {
                finishCard
                    .transition(pop(0.92))
            }
        }
        .preferredColorScheme(.dark)
        // Text grows with Dynamic Type, but is capped so the fixed-height bars never break.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .alert(
            shell.boosterPrompt == .extraBottle ? "Need more room?" : "Need a hint?",
            isPresented: Binding(
                get: { shell.boosterPrompt != nil },
                set: { if !$0 { shell.cancelBooster() } }
            )
        ) {
            Button("Watch Video") { shell.confirmBooster() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(shell.boosterPrompt == .extraBottle
                 ? "Watch a short video to add one extra bottle."
                 : "Watch a short video to see the next move.")
        }
        .sheet(isPresented: $shell.showMenu) {
            TopOffMenuView(shell: shell)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Accessibility and stuck banner

    /// SpriteKit draws the bottles but VoiceOver cannot see inside it, so each bottle gets an
    /// invisible element here, placed over it. The overlay ignores touches; gameplay still goes
    /// straight to the scene, and VoiceOver's activate gesture calls `activateBottle`.
    private var boardAccessibility: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(shell.bottleAccessibility) { bottle in
                    Color.clear
                        .frame(width: bottle.frame.width, height: bottle.frame.height)
                        .position(x: bottle.frame.midX, y: proxy.size.height - bottle.frame.midY)
                        .accessibilityElement()
                        .accessibilityLabel(bottle.label)
                        .accessibilityValue(bottle.value)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { shell.activateBottle(bottle.id) }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Shown when the board can no longer be finished. Never blocks play and never costs anything.
    private var stuckBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't be finished")
                    .scaledFont(14, .bold)
                Text("Undo a few moves or restart")
                    .scaledFont(11, .medium)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 4)
            if shell.canUndo {
                Button("Undo", action: shell.undo)
                    .buttonStyle(BannerButtonStyle(prominent: true))
            }
            Button("Restart", action: shell.restart)
                .buttonStyle(BannerButtonStyle(prominent: !shell.canUndo))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.orange.opacity(0.5), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
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
                    Text(shell.levelLabel)
                        .scaledFont(15, .heavy)
                        .tracking(3)
                        .foregroundStyle(.white)

                    if shell.isDaily {
                        Label("Streak \(shell.dailyStreak)", systemImage: "flame.fill")
                            .scaledFont(11, .bold)
                            .foregroundStyle(.orange)
                            .frame(height: 7 + 8)
                    } else if let number = shell.endlessNumber {
                        Label("Level \(number)", systemImage: "infinity")
                            .scaledFont(11, .bold)
                            .foregroundStyle(.mint)
                            .frame(height: 7 + 8)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(0..<shell.levelCount, id: \.self) { index in
                                Capsule()
                                    .fill(dotColor(for: index))
                                    .frame(width: index == shell.levelIndex ? 20 : 7, height: 7)
                            }
                        }
                        .animation(.spring(duration: 0.35), value: shell.levelIndex)
                    }

                    Text(shell.moves == 1 ? "1 move" : "\(shell.moves) moves")
                        .scaledFont(12, .semibold)
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: shell.moves)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shell.levelLabel). Open level select")

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
            labelledButton(
                systemName: "lightbulb.fill", title: "Hint",
                enabled: !shell.didFinishPrototype && !shell.boosterBusy,
                adBadge: shell.boostersUseAds, action: shell.hint
            )
            labelledButton(
                systemName: "plus.square.fill", title: "Bottle",
                enabled: shell.canAddBottle && !shell.didFinishPrototype && !shell.boosterBusy,
                adBadge: shell.boostersUseAds, action: shell.addBottle
            )
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
                .scaledFont(15, .bold)
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
                .scaledFont(28, .heavy)
            Text("\(shell.totalStars) of \(shell.levelCount * 3) stars")
                .scaledFont(15, .medium)
                .foregroundStyle(.white.opacity(0.65))

            Button {
                shell.showMenu = true
                shell.dismissFinish()
            } label: {
                Text("Pick a Level")
                    .scaledFont(17, .bold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 6)

            Button("Play from the Start") {
                shell.playAgain()
            }
            .scaledFont(15, .semibold)
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
        adBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
                    .overlay(alignment: .topTrailing) {
                        if adBadge {
                            // Marks a booster that is earned by watching a video.
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.black)
                                .frame(width: 18, height: 18)
                                .background(.yellow, in: Circle())
                                .offset(x: 4, y: -2)
                        }
                    }
                Text(title)
                    .scaledFont(11, .bold)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.2), value: enabled)
        .accessibilityLabel(adBadge ? "\(title), watch a video to use" : title)
    }
}

/// Rounded system text that grows with the player's Dynamic Type setting. At the default size it
/// is identical to a fixed `size`, so the layout is unchanged.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

private extension View {
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }
}

private struct BannerButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(14, .bold)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(prominent ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
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
                        .scaledFont(28, .heavy)
                    Spacer()
                    Label("\(shell.totalStars)", systemImage: "star.fill")
                        .scaledFont(16, .bold)
                        .foregroundStyle(.yellow)
                }

                dailyCard

                endlessCard

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

                if shell.privacyOptionsRequired {
                    Button("Ad privacy choices") { shell.showPrivacyOptions() }
                        .scaledFont(15, .semibold)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Text("Colour symbols draw a shape on each colour so the puzzle never depends on colour alone.")
                    .scaledFont(12, .medium)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(22)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.14).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var dailyCard: some View {
        let solved = shell.dailyMoves
        return Button {
            shell.playDaily()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Puzzle")
                        .scaledFont(18, .heavy)
                    Text(solved.map { "Solved in \($0) moves" } ?? "A new board every day")
                        .scaledFont(13, .medium)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(shell.dailyStreak)", systemImage: "flame.fill")
                        .scaledFont(16, .bold)
                        .foregroundStyle(.orange)
                    Text("day streak")
                        .scaledFont(10, .semibold)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.orange.opacity(0.22), .orange.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.orange.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Daily puzzle, \(shell.dailyStreak) day streak")
    }

    private var endlessCard: some View {
        Button {
            shell.playEndless()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "infinity")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.mint)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Endless")
                        .scaledFont(18, .heavy)
                    Text("One new board after another")
                        .scaledFont(13, .medium)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(shell.endlessReached == 0 ? "Start" : "Level \(shell.nextEndlessNumber)")
                        .scaledFont(16, .bold)
                        .foregroundStyle(.mint)
                    Text(shell.endlessReached == 0 ? "" : "\(shell.endlessReached) solved")
                        .scaledFont(10, .semibold)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.mint.opacity(0.20), .mint.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.mint.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Endless mode, next is level \(shell.nextEndlessNumber)")
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
                        .scaledFont(24, .black)
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
                .scaledFont(16, .semibold)
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
    @Published private(set) var dailyLevel: TopOffLevel?
    @Published private(set) var endlessNumber: Int?
    @Published private(set) var isStuck = false
    @Published private(set) var bottleAccessibility: [BottleAccessibility] = []
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var boosterBusy = false
    @Published var boosterPrompt: TopOffBooster?
    @Published var showMenu = false

    private let levels = TopOffLevels.campaign
    private let store = TopOffProgressStore()
    private static let log = Logger(subsystem: "ai.knowlly.topoff", category: "boosters")
    private let ads: TopOffAds
    private let boosters: TopOffBoosterService
    private let feedback = TopOffFeedback.makeController()

    var levelNumber: Int { min(levelIndex + 1, levels.count) }
    var levelCount: Int { levels.count }
    var isDaily: Bool { dailyLevel != nil }
    var isEndless: Bool { endlessNumber != nil }
    var levelLabel: String {
        if isDaily { return "DAILY" }
        if isEndless { return "ENDLESS" }
        return "LEVEL \(levelNumber)"
    }
    var currentLevel: TopOffLevel {
        if let dailyLevel { return dailyLevel }
        if let endlessNumber { return EndlessPuzzle.level(number: endlessNumber) }
        return levels[levelIndex]
    }
    /// The endless level the menu resumes at.
    var nextEndlessNumber: Int { progress.endlessReached + 1 }
    var endlessReached: Int { progress.endlessReached }
    var levelHasHiddenLayers: Bool { currentLevel.hasHiddenLayers }

    private var today: Int { DailyPuzzle.dayNumber(for: Date()) }
    var dailyStreak: Int { progress.dailyStreak(today: today) }
    var dailyMoves: Int? { progress.dailyBest[today] }

    var totalStars: Int {
        levels.indices.reduce(0) { $0 + stars(forLevelAt: $1) }
    }

    init() {
        var progress = store.load()
        #if DEBUG
        // Fills the level grid and streak for App Store screenshots. Never saved.
        if ProcessInfo.processInfo.environment["TOPOFF_DEMO_PROGRESS"] != nil {
            progress = TopOffProgress()
            for level in TopOffLevels.campaign.prefix(7) {
                progress.bestMoves[level.id] = level.solution.count
            }
            let today = DailyPuzzle.dayNumber(for: Date())
            for offset in 1...4 { progress.dailyBest[today - offset] = 12 }
            for number in 1...5 { progress.endlessBest[number] = 10 }
        }
        #endif
        self.progress = progress

        let ads = TopOffAds()
        self.ads = ads
        self.boosters = TopOffBoosterService(
            provider: ads.provider,
            receipts: UserDefaultsRewardReceiptStore()
        )

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
        if ProcessInfo.processInfo.environment["TOPOFF_AUTOPLAY"] != nil
            || ProcessInfo.processInfo.environment["TOPOFF_AUTOPLAY_ALL"] != nil {
            first.debugAutoplay(TopOffLevels.campaign[startIndex].solution)
        }
        if ProcessInfo.processInfo.environment["TOPOFF_RANDOMPLAY"] != nil {
            first.debugRandomPlay()
        }
        #endif
        flashTitle()
        Task { [weak self] in
            await ads.prepare()
            self?.privacyOptionsRequired = ads.privacyOptionsRequired
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOPOFF_MENU"] != nil { showMenu = true }
        if ProcessInfo.processInfo.environment["TOPOFF_DAILY"] != nil { playDaily() }
        if let raw = ProcessInfo.processInfo.environment["TOPOFF_ENDLESS"], let n = Int(raw) {
            dailyLevel = nil
            endlessNumber = max(1, n)
            loadCurrentLevel()
        }
        if ProcessInfo.processInfo.environment["TOPOFF_AUTOHINT"] != nil {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                self?.hint()
            }
        }
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

    func activateBottle(_ index: Int) { scene.activateBottle(index) }
    func undo() { scene.undo() }
    func restart() { scene.restart() }
    // MARK: Boosters

    /// The first levels teach the game, so they never involve ads.
    private var isOnboarding: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOPOFF_SKIP_ONBOARDING"] != nil { return false }
        #endif
        return progress.bestMoves.count < 2
    }

    /// Whether the booster buttons should carry the "watch a video" badge.
    var boostersUseAds: Bool { ads.isConfigured && !isOnboarding }

    func hint() { requestBooster(.hint) }
    func addBottle() { requestBooster(.extraBottle) }

    func confirmBooster() {
        guard let booster = boosterPrompt else { return }
        boosterPrompt = nil
        Task { await grant(booster) }
    }

    func cancelBooster() { boosterPrompt = nil }

    func showPrivacyOptions() {
        Task { await ads.presentPrivacyOptions() }
    }

    private func boosterKey(_ booster: TopOffBooster) -> String {
        "\(booster.rawValue)-\(currentLevel.id)"
    }

    private func boosterContext(for booster: TopOffBooster) -> BoosterContext {
        BoosterContext(
            levelID: currentLevel.id,
            sequence: (progress.boosterUses[boosterKey(booster)] ?? 0) + 1,
            isOnboarding: isOnboarding,
            canRequestAds: ads.canRequestAds
        )
    }

    private func requestBooster(_ booster: TopOffBooster) {
        guard !boosterBusy, boosterPrompt == nil else { return }
        // Never ask for a video to earn something that cannot work.
        switch booster {
        case .hint:
            guard scene.hintAvailable else {
                scene.rejectHint()
                return
            }
        case .extraBottle: guard canAddBottle else { return }
        }
        Task {
            let ready = await boosters.isAdReady(for: booster, context: boosterContext(for: booster))
            Self.log.info("booster \(booster.rawValue, privacy: .public): adReady=\(ready) canRequestAds=\(self.ads.canRequestAds) onboarding=\(self.isOnboarding)")
            if ready {
                boosterPrompt = booster
            } else {
                await grant(booster)
            }
        }
    }

    private func grant(_ booster: TopOffBooster) async {
        boosterBusy = true
        defer { boosterBusy = false }
        let outcome = await boosters.request(booster, context: boosterContext(for: booster))
        Self.log.info("booster \(booster.rawValue, privacy: .public) outcome: \(String(describing: outcome), privacy: .public)")
        guard outcome.isGranted else { return }
        let key = boosterKey(booster)
        update { $0.boosterUses[key, default: 0] += 1 }
        switch booster {
        case .hint: scene.showHint()
        case .extraBottle: scene.addExtraBottle()
        }
    }

    func playDaily() {
        showMenu = false
        withAnimation(.spring(duration: 0.3)) {
            didFinishPrototype = false
            result = nil
        }
        endlessNumber = nil
        dailyLevel = DailyPuzzle.level(forDay: today)
        loadCurrentLevel()
    }

    func playEndless() {
        showMenu = false
        withAnimation(.spring(duration: 0.3)) {
            didFinishPrototype = false
            result = nil
        }
        dailyLevel = nil
        endlessNumber = nextEndlessNumber
        loadCurrentLevel()
    }

    func play(levelAt index: Int) {
        guard isUnlocked(index) else { return }
        showMenu = false
        dailyLevel = nil
        endlessNumber = nil
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
        let level = currentLevel
        let daily = isDaily
        let endless = endlessNumber
        let previousBest: Int?
        if daily {
            previousBest = progress.dailyBest[level.id]
        } else if let endless {
            previousBest = progress.endlessBest[endless]
        } else {
            previousBest = progress.bestMoves[level.id]
        }
        let isBest = previousBest.map { moves < $0 } ?? true
        if isBest {
            update {
                if daily {
                    // Key by the puzzle's own day so a puzzle opened before midnight still counts for its day.
                    $0.dailyBest[level.id] = moves
                } else if let endless {
                    $0.endlessBest[endless] = moves
                } else {
                    $0.bestMoves[level.id] = moves
                }
            }
        }

        withAnimation(.spring(duration: 0.4)) {
            result = Result(stars: level.stars(forMoves: moves), moves: moves, isBest: isBest)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeIn(duration: 0.2)) { self?.result = nil }
            if daily {
                self?.leaveDaily()
            } else if let endless {
                self?.endlessNumber = endless + 1
                self?.loadCurrentLevel()
            } else {
                self?.advance()
            }
        }
    }

    /// After a daily puzzle, go back to where the campaign was and show the streak in the menu.
    private func leaveDaily() {
        dailyLevel = nil
        if let next = levels.firstIndex(where: { progress.bestMoves[$0.id] == nil }) {
            levelIndex = next
        }
        loadCurrentLevel()
        showMenu = true
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
        let next = TopOffScene(level: currentLevel, feedback: feedback)
        apply(progress, to: next)
        attachHandlers(to: next)
        #if DEBUG
        // End-to-end check: keep playing the reference solution on every level that loads.
        if ProcessInfo.processInfo.environment["TOPOFF_AUTOPLAY_ALL"] != nil {
            next.debugAutoplay(currentLevel.solution)
        }
        #endif
        moves = 0
        canUndo = false
        canAddBottle = true
        isStuck = false

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
        scene.onStuckChange = { [weak self] stuck in
            withAnimation(.easeOut(duration: 0.25)) { self?.isStuck = stuck }
        }
        scene.onAccessibilityChange = { [weak self] bottles in
            self?.bottleAccessibility = bottles
        }
        scene.onStateChange = { [weak self] moves, canUndo, canAddBottle in
            self?.moves = moves
            self?.canUndo = canUndo
            self?.canAddBottle = canAddBottle
        }
    }
}
