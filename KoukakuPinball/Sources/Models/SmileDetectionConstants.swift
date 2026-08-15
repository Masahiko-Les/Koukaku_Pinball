import Foundation

/// Tunable constants for smile detection. Adjust here to retune sensitivity
/// without touching the detection logic itself.
enum SmileDetectionConstants {
    /// How far above baseline `mouthSmileLeft` / `mouthSmileRight` must rise to count as a smile.
    static let smileThreshold: Float = 0.2
    /// Consecutive frames a condition must hold before the ON/OFF state flips (debounce).
    static let requiredFrames: Int = 2
    /// Duration of the neutral-expression calibration phase, in seconds.
    static let calibrationDuration: TimeInterval = 2.0
    /// Upper bound applied to a measured baseline. Guards against a calibration that
    /// wasn't perfectly neutral (e.g. mid-motion) from making the smile threshold nearly unreachable.
    static let maxBaseline: Float = 0.3
}
