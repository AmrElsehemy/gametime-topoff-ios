import Foundation
import GameTimeExperience

/// Top Off's feel: which haptic and which sound goes with each semantic event. The engines that
/// play them live in GameTimeKit; only these cue tables are specific to this game.
@MainActor
enum TopOffFeedback {
    static func makeController() -> GameFeedbackController {
        GameFeedbackController(
            audio: SynthAudioController(sounds: sounds),
            haptics: CoreHapticsController(patterns: haptics)
        )
    }

    // MARK: Haptics

    static let haptics: [GameFeedbackEvent: HapticPattern] = [
        .placement: HapticPattern([.tap(intensity: 0.5, sharpness: 0.6)]),
        .invalidMove: HapticPattern([
            .tap(intensity: 0.85, sharpness: 0.9),
            .tap(at: 0.08, intensity: 0.7, sharpness: 0.9)
        ]),
        .conflict: HapticPattern([
            .tap(intensity: 0.85, sharpness: 0.9),
            .tap(at: 0.08, intensity: 0.7, sharpness: 0.9)
        ]),
        .undo: HapticPattern([.tap(intensity: 0.4, sharpness: 0.3)]),
        // A soft glug: a tap as the liquid starts, then a swelling rumble.
        .pour: HapticPattern(
            [
                .tap(intensity: 0.55, sharpness: 0.3),
                .rumble(at: 0.04, duration: 0.55, intensity: 0.55, sharpness: 0.15)
            ],
            intensityCurve: [
                .init(time: 0, value: 0.5),
                .init(time: 0.25, value: 1),
                .init(time: 0.6, value: 0.2)
            ],
            curveStart: 0.04
        ),
        .milestone: HapticPattern([
            .tap(intensity: 0.9, sharpness: 0.5),
            .tap(at: 0.1, intensity: 0.6, sharpness: 0.7)
        ]),
        .hint: HapticPattern([
            .tap(intensity: 0.35, sharpness: 1),
            .tap(at: 0.06, intensity: 0.25, sharpness: 1)
        ]),
        .solve: HapticPattern([
            .tap(intensity: 0.6, sharpness: 0.5),
            .tap(at: 0.12, intensity: 0.75, sharpness: 0.6),
            .tap(at: 0.24, intensity: 0.95, sharpness: 0.7),
            .rumble(at: 0.3, duration: 0.5, intensity: 0.45, sharpness: 0.2)
        ])
    ]

    // MARK: Sounds

    static let sounds: [GameFeedbackEvent: SynthSound] = {
        let invalid = SynthSound.render(duration: 0.2) { t in
            // A short downward thump.
            let phase = 2 * .pi * 160 * (1 - exp(-t * 6)) / 6
            return 0.55 * sin(phase) * exp(-t * 16)
        }
        return [
            .placement: .render(duration: 0.1) { t in
                0.35 * sin(2 * .pi * 700 * t) * exp(-t * 45)
                    + 0.12 * sin(2 * .pi * 1400 * t) * exp(-t * 70)
            },
            .invalidMove: invalid,
            .conflict: invalid,
            .undo: .render(duration: 0.18) { t in
                0.3 * sin(2 * .pi * (600 * t - 600 * t * t)) * exp(-t * 14)
            },
            .pour: pour,
            .milestone: .render(duration: 0.55) { t in
                SynthSound.bell(880, at: t, decay: 7) * 0.4
                    + SynthSound.bell(1318, at: t - 0.09, decay: 7) * 0.4
            },
            // Reused for "a hidden layer was revealed".
            .hint: .render(duration: 0.4) { t in
                SynthSound.bell(1760, at: t, decay: 13) * 0.3
                    + SynthSound.bell(2349, at: t - 0.06, decay: 13) * 0.3
            },
            .solve: .render(duration: 1.4) { t in
                [523.0, 659, 784, 1047, 1319].enumerated().reduce(0) { sum, note in
                    sum + SynthSound.bell(note.element, at: t - Double(note.offset) * 0.1, decay: 4.5) * 0.28
                }
            }
        ]
    }()

    /// A soft bubbling pour: random chirping bubbles over a faint low-passed hiss.
    private static var pour: SynthSound {
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
        return SynthSound.render(duration: duration) { t in
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
}
