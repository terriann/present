import AppKit

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    enum SoundEffect: String, CaseIterable {
        case approach
        case blow
        case dip
        case shimmer

        var fileExtension: String {
            switch self {
            case .blow: return "aiff"
            default: return "wav"
            }
        }
    }

    private var sounds: [SoundEffect: NSSound] = [:]
    var isEnabled = true

    private init() {
        // Pre-load all sounds from the bundle
        for effect in SoundEffect.allCases {
            if let url = Bundle.main.url(forResource: effect.rawValue, withExtension: effect.fileExtension),
               let sound = NSSound(contentsOf: url, byReference: false) {
                sounds[effect] = sound
            }
        }
    }

    func configure(soundEnabled: Bool) {
        isEnabled = soundEnabled
    }

    func play(_ effect: SoundEffect) {
        guard isEnabled, let sound = sounds[effect] else { return }
        sound.stop()
        sound.play()
    }
}
