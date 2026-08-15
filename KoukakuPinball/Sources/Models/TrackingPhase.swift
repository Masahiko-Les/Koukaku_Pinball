import Foundation

/// High-level lifecycle of the face-tracking screen.
enum TrackingPhase: Equatable {
    /// Device does not support `ARFaceTrackingConfiguration`.
    case unsupported
    /// Waiting for the face to be detected for the first time.
    case waitingForFace
    /// Face detected; sampling a neutral expression to compute the baseline.
    case calibrating
    /// Calibration finished; smile detection is active.
    case ready
}
