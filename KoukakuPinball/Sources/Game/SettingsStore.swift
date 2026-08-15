import Foundation

/// User-controlled app preferences, persisted via UserDefaults.
///
/// Kept separate from `GameState` (which tracks the current play session) since
/// these are long-lived settings that survive across games and app launches.
final class SettingsStore: ObservableObject {
    @Published var isSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(isSoundEnabled, forKey: Keys.isSoundEnabled) }
    }

    private enum Keys {
        static let isSoundEnabled = "com.mfujita.koukakupinball.isSoundEnabled"
    }

    init() {
        if UserDefaults.standard.object(forKey: Keys.isSoundEnabled) == nil {
            isSoundEnabled = true
        } else {
            isSoundEnabled = UserDefaults.standard.bool(forKey: Keys.isSoundEnabled)
        }
    }
}
