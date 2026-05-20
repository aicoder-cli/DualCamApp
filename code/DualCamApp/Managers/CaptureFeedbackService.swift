import AudioToolbox
import Combine
import UIKit

@MainActor
final class CaptureFeedbackService: ObservableObject {
    enum Event {
        case photoCaptured
        case livePhotoShutterAccepted
        case recordingStarted
        case recordingStopped
        case captureFailed
    }

    enum Sound: SystemSoundID {
        case photoShutter = 1108
        case recordingStarted = 1117
        case recordingStopped = 1118
    }

    enum Haptic: Equatable {
        case mediumImpact
        case heavyImpact
        case successNotification
        case errorNotification
    }

    struct Performer {
        var playSound: @MainActor (Sound) -> Void
        var playHaptic: @MainActor (Haptic) -> Void

        static let live = Performer(
            playSound: { sound in
                AudioServicesPlaySystemSound(sound.rawValue)
            },
            playHaptic: { haptic in
                switch haptic {
                case .mediumImpact:
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred(intensity: 1.0)
                case .heavyImpact:
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.prepare()
                    generator.impactOccurred(intensity: 1.0)
                case .successNotification:
                    let generator = UINotificationFeedbackGenerator()
                    generator.prepare()
                    generator.notificationOccurred(.success)
                case .errorNotification:
                    let generator = UINotificationFeedbackGenerator()
                    generator.prepare()
                    generator.notificationOccurred(.error)
                }
            }
        )
    }

    private let performer: Performer

    init(performer: Performer? = nil) {
        self.performer = performer ?? .live
    }

    func perform(_ event: Event, enabled: Bool) {
        guard enabled else { return }

        switch event {
        case .photoCaptured:
            perform(sound: .photoShutter, haptics: [.mediumImpact])
        case .livePhotoShutterAccepted:
            perform(sound: .photoShutter, haptics: [.heavyImpact, .successNotification])
        case .recordingStarted:
            perform(sound: .recordingStarted, haptics: [.heavyImpact])
        case .recordingStopped:
            perform(sound: .recordingStopped, haptics: [.heavyImpact, .successNotification])
        case .captureFailed:
            performer.playHaptic(.errorNotification)
        }
    }

    private func perform(sound: Sound, haptics: [Haptic]) {
        haptics.forEach { performer.playHaptic($0) }
        performer.playSound(sound)
    }
}
