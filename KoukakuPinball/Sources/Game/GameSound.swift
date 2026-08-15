import AudioToolbox

/// Thin wrapper around built-in iOS system sounds. Using system sound IDs (rather
/// than bundled audio files) means there is nothing that can go missing at build
/// or run time — the sounds are always available on-device.
///
/// Every call takes `enabled` explicitly (from `SettingsStore.isSoundEnabled`)
/// rather than reading a shared/global flag, so this type stays a stateless enum.
enum GameSound {
    private static let flipperSoundID: SystemSoundID = 1104
    private static let bumperSoundID: SystemSoundID = 1025
    private static let ballLostSoundID: SystemSoundID = 1006

    static func playFlipper(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(flipperSoundID)
    }

    static func playBumper(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(bumperSoundID)
    }

    static func playBallLost(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(ballLostSoundID)
    }
}
