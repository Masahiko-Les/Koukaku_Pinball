import SwiftUI

/// The face-tracking calibration screen. Receives the shared `FaceTrackingManager`
/// from `RootView` rather than owning it, so state (calibration, session) survives tab switches.
struct ContentView: View {
    @ObservedObject var faceTrackingManager: FaceTrackingManager

    /// Sticks after the very first dismissal — the intro is a one-time explainer, not a
    /// per-launch splash. `FaceTrackingManager` separately persists the calibration baseline
    /// itself, so a returning user skips both this and calibration.
    @AppStorage("com.mfujita.koukakupinball.hasSeenIntro") private var hasSeenIntro = false

    var body: some View {
        if hasSeenIntro {
            trackingContent
        } else {
            IntroView { hasSeenIntro = true }
        }
    }

    private var trackingContent: some View {
        VStack(spacing: 20) {
            header

            statusCard
                .frame(minHeight: 140)

            Spacer(minLength: 0)

            if faceTrackingManager.phase == .ready {
                HStack(spacing: 48) {
                    SmileIndicatorCircle(
                        label: "左口角",
                        isActive: faceTrackingManager.smileState.isLeftSmileActive,
                        activeColor: .green
                    )
                    SmileIndicatorCircle(
                        label: "右口角",
                        isActive: faceTrackingManager.smileState.isRightSmileActive,
                        activeColor: .blue
                    )
                }
            }

            Spacer(minLength: 12)

            if GameConfig.debugMode {
                debugSection
                    .padding(.bottom, 12)
            }
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

    private var header: some View {
        VStack(spacing: 4) {
            Text("口角コントローラー")
                .font(.title2.bold())
            Text("口角を上げるとフリッパーが動きます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var statusCard: some View {
        statusContent
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch faceTrackingManager.phase {
        case .unsupported:
            EmptyView()
        case .waitingForFace:
            faceGuidanceView
        case .calibrating:
            calibratingView
        case .ready:
            if faceTrackingManager.isFaceDetected {
                if faceTrackingManager.didJustRecalibrate {
                    recalibratedView
                } else {
                    readyView
                }
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
                .multilineTextAlignment(.center)
        }
    }

    private var calibratingView: some View {
        VStack(spacing: 12) {
            Text("普通の表情で2秒間、正面を向いてください")
                .font(.headline)
                .multilineTextAlignment(.center)
            ProgressView(value: faceTrackingManager.calibrationProgress)
                .tint(.yellow)
                .padding(.horizontal, 20)
        }
    }

    /// Shown in place of `readyView` right after a recalibration completes, then
    /// auto-dismisses back to the normal ready state a couple seconds later.
    private var recalibratedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("口角が再登録されました。")
                .font(.headline)
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            faceTrackingManager.acknowledgeRecalibration()
        }
    }

    private var readyView: some View {
        VStack(spacing: 12) {
            Label("準備OK", systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
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

// MARK: - First-launch intro

private struct IntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "face.smiling")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("スマイルピンボールへようこそ")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("このピンボールゲームは、あなたの口角でフリッパーを動かします。\n初回のみインカメで口角を登録します。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Text("顔の映像や情報は端末外に送信されません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button(action: onContinue) {
                Text("はじめる")
                    .font(.system(.headline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    ContentView(faceTrackingManager: FaceTrackingManager())
}
