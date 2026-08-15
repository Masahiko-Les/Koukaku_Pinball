import SwiftUI

/// The face-tracking debug / calibration screen. Receives the shared `FaceTrackingManager`
/// from `RootView` rather than owning it, so state (calibration, session) survives tab switches.
struct ContentView: View {
    @ObservedObject var faceTrackingManager: FaceTrackingManager

    var body: some View {
        VStack(spacing: 16) {
            Text("口角コントローラー")
                .font(.title2).bold()
                .padding(.top, 12)

            statusSection
                .frame(minHeight: 120)

            Spacer(minLength: 0)

            HStack(spacing: 48) {
                SmileIndicatorCircle(
                    label: "LEFT",
                    isActive: faceTrackingManager.smileState.isLeftSmileActive,
                    activeColor: .green
                )
                SmileIndicatorCircle(
                    label: "RIGHT",
                    isActive: faceTrackingManager.smileState.isRightSmileActive,
                    activeColor: .blue
                )
            }

            Spacer(minLength: 12)

            debugSection
                .padding(.bottom, 12)
        }
        .padding()
        .overlay(alignment: .topTrailing) {
            CameraPreviewView(session: faceTrackingManager.session)
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .padding([.top, .trailing], 12)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch faceTrackingManager.phase {
        case .unsupported:
            EmptyView()
        case .waitingForFace:
            faceGuidanceView
        case .calibrating:
            calibratingView
        case .ready:
            if faceTrackingManager.isFaceDetected {
                readyView
            } else {
                faceGuidanceView
            }
        }
    }

    private var faceGuidanceView: some View {
        VStack(spacing: 8) {
            Image(systemName: "face.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("顔をカメラの正面に合わせてください")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var calibratingView: some View {
        VStack(spacing: 12) {
            Text("普通の表情で2秒間、正面を向いてください")
                .font(.headline)
                .multilineTextAlignment(.center)
            ProgressView(value: faceTrackingManager.calibrationProgress)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var readyView: some View {
        VStack(spacing: 12) {
            Text("準備OK")
                .font(.subheadline)
                .foregroundStyle(.green)

            HStack(spacing: 32) {
                smileValueView(title: "左口角", value: faceTrackingManager.smileState.mouthSmileLeft)
                smileValueView(title: "右口角", value: faceTrackingManager.smileState.mouthSmileRight)
            }
        }
    }

    private func smileValueView(title: String, value: Float) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(.title, design: .rounded))
                .monospacedDigit()
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEBUG")
                .font(.caption2).bold()
            Group {
                Text("baselineLeft: \(String(format: "%.2f", faceTrackingManager.baselineLeft))")
                Text("baselineRight: \(String(format: "%.2f", faceTrackingManager.baselineRight))")
                Text("mouthSmileLeft: \(String(format: "%.2f", faceTrackingManager.smileState.mouthSmileLeft))")
                Text("mouthSmileRight: \(String(format: "%.2f", faceTrackingManager.smileState.mouthSmileRight))")
                Text("LEFT判定: \(faceTrackingManager.smileState.isLeftSmileActive ? "ON" : "OFF")")
                Text("RIGHT判定: \(faceTrackingManager.smileState.isRightSmileActive ? "ON" : "OFF")")
                Text("FPS: \(String(format: "%.1f", faceTrackingManager.currentFPS))")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

#Preview {
    ContentView(faceTrackingManager: FaceTrackingManager())
}
