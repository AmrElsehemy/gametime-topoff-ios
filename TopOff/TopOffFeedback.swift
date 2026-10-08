import AudioToolbox
import Foundation
import UIKit
import GameTimeExperience

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
}

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

        let soundID: SystemSoundID
        switch event {
        case .invalidMove, .conflict:
            soundID = 1102
        case .solve, .milestone:
            soundID = 1025
        case .pour:
            soundID = 1104
        case .undo, .placement, .hint:
            soundID = 1105
        }

        AudioServicesPlaySystemSound(soundID)
    }
}
