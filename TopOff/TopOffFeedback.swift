import AVFoundation
import CoreHaptics
import Foundation
import UIKit
import GameTimeExperience

// MARK: - Haptics

final class TopOffHapticsController: HapticsControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            self.enabled = enabled
        }
    }

    func play(_ event: GameFeedbackEvent) {
        let shouldPlay = lock.withLock { enabled }
        guard shouldPlay else { return }

        Task { @MainActor in
            TopOffHapticEngine.shared.play(event)
        }
    }
}

/// Core Haptics patterns per event, with UIKit generators as a fallback on devices without it.
@MainActor
private final class TopOffHapticEngine {
    static let shared = TopOffHapticEngine()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play(_ event: GameFeedbackEvent) {
        guard supportsHaptics, let engine = preparedEngine() else {
            playFallback(event)
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events(for: event), parameterCurves: curves(for: event))
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallback(event)
        }
    }

    private func preparedEngine() -> CHHapticEngine? {
        if let engine { return engine }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak engine] in
                try? engine?.start()
            }
            try engine.start()
            self.engine = engine
            return engine
        } catch {
            return nil
        }
    }

    private func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func rumble(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func events(for event: GameFeedbackEvent) -> [CHHapticEvent] {
        switch event {
        case .placement:
            return [tap(0, 0.5, 0.6)]
        case .invalidMove, .conflict:
            return [tap(0, 0.85, 0.9), tap(0.08, 0.7, 0.9)]
        case .undo:
            return [tap(0, 0.4, 0.3)]
        case .pour:
            // A soft glug: a tap as the liquid starts, then a swelling rumble.
            return [tap(0, 0.55, 0.3), rumble(0.04, 0.55, 0.55, 0.15)]
        case .milestone:
            return [tap(0, 0.9, 0.5), tap(0.1, 0.6, 0.7)]
        case .hint:
            return [tap(0, 0.35, 1), tap(0.06, 0.25, 1)]
        case .solve:
            return [
                tap(0, 0.6, 0.5), tap(0.12, 0.75, 0.6), tap(0.24, 0.95, 0.7),
                rumble(0.3, 0.5, 0.45, 0.2)
            ]
        }
    }

    private func curves(for event: GameFeedbackEvent) -> [CHHapticParameterCurve] {
        guard event == .pour else { return [] }
        return [
            CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 0.5),
                    .init(relativeTime: 0.25, value: 1),
                    .init(relativeTime: 0.6, value: 0.2)
                ],
                relativeTime: 0.04
            )
        ]
    }

    private func playFallback(_ event: GameFeedbackEvent) {
        switch event {
        case .invalidMove, .conflict:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .solve, .milestone:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .pour:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.85)
        case .undo, .placement, .hint:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        }
    }
}

// MARK: - Audio

final class TopOffAudioController: AudioControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            self.enabled = enabled
        }
    }

    func play(_ event: GameFeedbackEvent) {
        let shouldPlay = lock.withLock { enabled }
        guard shouldPlay else { return }

        Task { @MainActor in
            TopOffSoundEngine.shared.play(event)
        }
    }
}

/// Every sound is synthesised at first use, so the app ships no audio files and the sounds stay
/// tunable in code. One player node per event lets a new play cut off the previous one.
@MainActor
private final class TopOffSoundEngine {
    static let shared = TopOffSoundEngine()

    private let engine = AVAudioEngine()
    private var players: [GameFeedbackEvent: AVAudioPlayerNode] = [:]
    private var buffers: [GameFeedbackEvent: AVAudioPCMBuffer] = [:]
    private var isReady = false

    private static let rate = 44_100.0
    private static let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!

    func play(_ event: GameFeedbackEvent) {
        prepareIfNeeded()
        guard isReady, let player = players[event], let buffer = buffers[event] else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func prepareIfNeeded() {
        guard !isReady else { return }

        // Ambient: mixes with the user's music and respects the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        for event in GameFeedbackEvent.allCases {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.format)
            players[event] = player
            buffers[event] = Self.makeBuffer(for: event)
        }
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
            isReady = true
        } catch {
            isReady = false
        }
    }

    // MARK: Synthesis

    private static func makeBuffer(for event: GameFeedbackEvent) -> AVAudioPCMBuffer {
        switch event {
        case .placement:
            return render(duration: 0.1) { t in
                0.35 * sin(2 * .pi * 700 * t) * exp(-t * 45)
                    + 0.12 * sin(2 * .pi * 1400 * t) * exp(-t * 70)
            }
        case .invalidMove, .conflict:
            return render(duration: 0.2) { t in
                // A short downward thump.
                let phase = 2 * .pi * 160 * (1 - exp(-t * 6)) / 6
                return 0.55 * sin(phase) * exp(-t * 16)
            }
        case .undo:
            return render(duration: 0.18) { t in
                let phase = 2 * .pi * (600 * t - 600 * t * t)
                return 0.3 * sin(phase) * exp(-t * 14)
            }
        case .pour:
            return pourBuffer()
        case .milestone:
            return render(duration: 0.55) { t in
                bell(880, t, 7) * 0.4 + bell(1318, t - 0.09, 7) * 0.4
            }
        case .hint:
            return render(duration: 0.4) { t in
                bell(1760, t, 13) * 0.3 + bell(2349, t - 0.06, 13) * 0.3
            }
        case .solve:
            let notes: [Double] = [523, 659, 784, 1047, 1319]
            return render(duration: 1.4) { t in
                var sum = 0.0
                for (index, frequency) in notes.enumerated() {
                    sum += bell(frequency, t - Double(index) * 0.1, 4.5) * 0.28
                }
                return sum
            }
        }
    }

    /// A soft bubbling pour: random chirping bubbles over a faint low-passed hiss.
    private static func pourBuffer() -> AVAudioPCMBuffer {
        let duration = 0.85
        var seed: UInt64 = 0x1234_5678
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }

        var bubbles: [(start: Double, base: Double, gain: Double)] = []
        var time = 0.04
        while time < duration - 0.1 {
            bubbles.append((time, 280 + random() * 700, 0.1 + random() * 0.14))
            time += 0.012 + random() * 0.03
        }

        var hiss = 0.0
        return render(duration: duration) { t in
            var sum = 0.0
            for bubble in bubbles {
                let local = t - bubble.start
                guard local >= 0, local < 0.09 else { continue }
                let frequency = bubble.base * (1 + 7 * local)
                sum += bubble.gain * sin(2 * .pi * frequency * local) * exp(-local * 48)
            }
            hiss += 0.08 * ((random() * 2 - 1) - hiss)
            sum += 0.05 * hiss
            let envelope = min(t / 0.06, 1) * min((duration - t) / 0.18, 1)
            return sum * envelope
        }
    }

    private static func bell(_ frequency: Double, _ t: Double, _ decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        return sin(2 * .pi * frequency * t) * exp(-t * decay)
            + 0.3 * sin(2 * .pi * frequency * 2.76 * t) * exp(-t * decay * 1.8)
    }

    private static func render(duration: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            // Clamp so no event can ever clip the output.
            data[index] = Float(max(-0.95, min(0.95, sample(Double(index) / rate))))
        }
        return buffer
    }
}
