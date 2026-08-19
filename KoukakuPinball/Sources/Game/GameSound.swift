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
    // 1006 (an SMS-receipt tone) ignores the ring/silent switch — that classification is
    // baked into the system sound ID itself, not something AudioServicesPlaySystemSound can
    // override. 1103 is a plain keyboard-click tone, same "always respects mute" family as
    // flipperSoundID above.
    private static let ballLostSoundID: SystemSoundID = 1103

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
