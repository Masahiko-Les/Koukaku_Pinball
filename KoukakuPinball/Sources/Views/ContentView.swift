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

            cameraPreview

            statusCard
                .frame(minHeight: 140)

            Spacer()

            if faceTrackingManager.phase == .ready {
                recalibrateButton
            }

            if GameConfig.debugMode {
                debugSection
                    .padding(.bottom, 12)
            }
        }
        .padding()
    }

    private var header: some View {
        Text("口角チェック")
            .font(.title2.bold())
            .padding(.top, 12)
    }

    private var cameraPreview: some View {
        CameraPreviewView(session: faceTrackingManager.session)
            // Explicit width AND height, rather than .aspectRatio(_:contentMode:) deriving
            // height from a proposed size — ARSCNView doesn't report a usable intrinsic
            // size, and letting SwiftUI infer its height from an unconstrained proposal is
            // what was making this taller than intended and overlapping statusCard below it.
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.secondary.opacity(0.3)))
    }

    /// Redoes calibration from scratch without leaving this tab — a quicker path to the
    /// same effect as Settings' "口角を登録し直す", for when detection feels off right now.
    private var recalibrateButton: some View {
        Button {
            faceTrackingManager.recalibrate()
        } label: {
            Text("口角を再調整する")
                .font(.system(.subheadline, design: .rounded).bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow, in: Capsule())
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 24)
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

            Text("笑うとフリッパーが動きます。")
                .font(.subheadline.bold())
                .foregroundStyle(.green)

            HStack(spacing: 32) {
                smileValueView(title: "左口角", value: faceTrackingManager.smileState.mouthSmileLeft)
                smileValueView(title: "右口角", value: faceTrackingManager.smileState.mouthSmileRight)
            }

            // Matches the real board's flipper spacing: pivots ~0.44w apart, paddles
            // ~0.21w long each, leaving the paddles' resting tips only a few percent of
            // the screen width apart — proportionally much tighter than a plain centered gap.
            //
            // The extra height here isn't padding — a capsule pivoting from its edge sweeps
            // a much taller arc than its own 18pt thickness (roughly ±45pt at these angles),
            // and without reserving that as real layout height, the swing visually overlaps
            // whatever sits above this row instead of rotating in its own clear space.
            HStack(spacing: 24) {
                FlipperIndicator(
                    isActive: faceTrackingManager.smileState.isLeftSmileActive,
                    mirrored: false
                )
                FlipperIndicator(
                    isActive: faceTrackingManager.smileState.isRightSmileActive,
                    mirrored: true
                )
            }
            .frame(height: 90)
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

// MARK: - Left/right smile indicators

/// A red flipper-paddle shape matching the actual in-game flipper as closely as this
/// smaller UI context allows: same color (`PinballScene.flipperColor`), same rest/swing
/// angle magnitudes (`flipperRestDegrees` / `flipperUpDegrees`), and — critically — it
/// pivots from one *end*, not its center, exactly like `makeFlipperNode`'s paddle does
/// around `pinFlipper`'s anchor. A center-rotated capsule reads as generic; an
/// edge-pivoted one reads as an actual flipper.
private struct FlipperIndicator: View {
    let isActive: Bool
    /// The right flipper is the left flipper's mirror image: pivot on the opposite edge,
    /// paddle swinging the opposite way.
    let mirrored: Bool

    private let restDegrees: Double = 25
    private let swingDegrees: Double = 57

    private var angle: Double {
        let sign: Double = mirrored ? -1 : 1
        let rest = sign * restDegrees
        guard isActive else { return rest }
        return rest - sign * swingDegrees
    }

    var body: some View {
        Capsule()
            .fill(Color(red: 0.87, green: 0.27, blue: 0.24))
            .frame(width: 84, height: 18)
            .rotationEffect(.degrees(angle), anchor: mirrored ? .trailing : .leading)
            .animation(.easeOut(duration: 0.06), value: isActive)
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
