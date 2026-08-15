import ARKit
import Combine
import Foundation

/// Owns the ARKit face-tracking session and publishes smile-detection state.
///
/// This type has no UI or game dependency — `smileState.isLeftSmileActive` /
/// `isRightSmileActive` are the two boolean signals meant to eventually drive
/// SpriteKit flippers. Face image data and blend shape values never leave the
/// device and are not persisted anywhere.
final class FaceTrackingManager: NSObject, ObservableObject {

    @Published private(set) var phase: TrackingPhase
    @Published private(set) var isFaceDetected: Bool = false
    @Published private(set) var smileState = SmileInputState()
    @Published private(set) var baselineLeft: Float = 0
    @Published private(set) var baselineRight: Float = 0
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var currentFPS: Double = 0

    /// Exposed so an optional camera preview (`CameraPreviewView`) can attach to the same session.
    let session = ARSession()

    var isSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    private var calibrationStartTimestamp: TimeInterval?
    private var calibrationLeftSamples: [Float] = []
    private var calibrationRightSamples: [Float] = []

    private var leftAboveStreak = 0
    private var leftBelowStreak = 0
    private var rightAboveStreak = 0
    private var rightBelowStreak = 0

    private var lastFrameTimestamp: TimeInterval?

    override init() {
        phase = ARFaceTrackingConfiguration.isSupported ? .waitingForFace : .unsupported
        super.init()
    }

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        session.run(configuration)
    }

    func pause() {
        session.pause()
    }

    // MARK: - Frame handling (always called on the main thread)

    private func handle(frame: ARFrame) {
        updateFPS(timestamp: frame.timestamp)

        guard let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor else {
            return
        }

        let blendShapes = faceAnchor.blendShapes
        smileState.mouthSmileLeft = blendShapes[.mouthSmileLeft]?.floatValue ?? 0
        smileState.mouthSmileRight = blendShapes[.mouthSmileRight]?.floatValue ?? 0
        smileState.mouthFrownLeft = blendShapes[.mouthFrownLeft]?.floatValue ?? 0
        smileState.mouthFrownRight = blendShapes[.mouthFrownRight]?.floatValue ?? 0

        switch phase {
        case .unsupported, .waitingForFace:
            break
        case .calibrating:
            progressCalibration(timestamp: frame.timestamp)
        case .ready:
            updateSmileActivation()
        }
    }

    private func updateFPS(timestamp: TimeInterval) {
        defer { lastFrameTimestamp = timestamp }
        guard let last = lastFrameTimestamp else { return }
        let delta = timestamp - last
        guard delta > 0 else { return }
        let instantaneousFPS = 1.0 / delta
        currentFPS = currentFPS == 0 ? instantaneousFPS : currentFPS * 0.9 + instantaneousFPS * 0.1
    }

    private func progressCalibration(timestamp: TimeInterval) {
        if calibrationStartTimestamp == nil {
            calibrationStartTimestamp = timestamp
            calibrationLeftSamples.removeAll()
            calibrationRightSamples.removeAll()
        }
        calibrationLeftSamples.append(smileState.mouthSmileLeft)
        calibrationRightSamples.append(smileState.mouthSmileRight)

        let elapsed = timestamp - (calibrationStartTimestamp ?? timestamp)
        calibrationProgress = min(elapsed / SmileDetectionConstants.calibrationDuration, 1.0)

        if elapsed >= SmileDetectionConstants.calibrationDuration {
            baselineLeft = min(average(calibrationLeftSamples), SmileDetectionConstants.maxBaseline)
            baselineRight = min(average(calibrationRightSamples), SmileDetectionConstants.maxBaseline)
            resetActivationStreaks()
            phase = .ready
        }
    }

    private func average(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private func updateSmileActivation() {
        let leftAboveThreshold = smileState.mouthSmileLeft > baselineLeft + SmileDetectionConstants.smileThreshold
        let rightAboveThreshold = smileState.mouthSmileRight > baselineRight + SmileDetectionConstants.smileThreshold

        smileState.isLeftSmileActive = updatedActivation(
            isAboveThreshold: leftAboveThreshold,
            aboveStreak: &leftAboveStreak,
            belowStreak: &leftBelowStreak,
            currentlyActive: smileState.isLeftSmileActive
        )
        smileState.isRightSmileActive = updatedActivation(
            isAboveThreshold: rightAboveThreshold,
            aboveStreak: &rightAboveStreak,
            belowStreak: &rightBelowStreak,
            currentlyActive: smileState.isRightSmileActive
        )
    }

    /// Debounces raw threshold crossings so a single noisy frame can't flip the ON/OFF state.
    private func updatedActivation(
        isAboveThreshold: Bool,
        aboveStreak: inout Int,
        belowStreak: inout Int,
        currentlyActive: Bool
    ) -> Bool {
        if isAboveThreshold {
            aboveStreak += 1
            belowStreak = 0
        } else {
            belowStreak += 1
            aboveStreak = 0
        }

        if aboveStreak >= SmileDetectionConstants.requiredFrames {
            return true
        } else if belowStreak >= SmileDetectionConstants.requiredFrames {
            return false
        }
        return currentlyActive
    }

    private func resetActivationStreaks() {
        leftAboveStreak = 0
        leftBelowStreak = 0
        rightAboveStreak = 0
        rightBelowStreak = 0
        smileState.isLeftSmileActive = false
        smileState.isRightSmileActive = false
    }

    private func beginWaitingForFace() {
        phase = .waitingForFace
        calibrationStartTimestamp = nil
        calibrationProgress = 0
        resetActivationStreaks()
    }
}

// MARK: - ARSessionDelegate

extension FaceTrackingManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(frame: frame)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard anchors.contains(where: { $0 is ARFaceAnchor }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFaceDetected = true
            if self.phase == .waitingForFace {
                self.phase = .calibrating
                self.calibrationStartTimestamp = nil
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard anchors.contains(where: { $0 is ARFaceAnchor }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFaceDetected = false
            if self.phase == .calibrating {
                self.beginWaitingForFace()
            } else if self.phase == .ready {
                // Force flipper input off while tracking is lost, rather than leaving
                // isLeftSmileActive/isRightSmileActive stuck at whatever they last were.
                self.resetActivationStreaks()
            }
        }
    }
}
