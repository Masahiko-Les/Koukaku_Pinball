import SpriteKit
import SwiftUI

/// Hosts the pinball game: creates the `PinballScene` sized to the real device screen,
/// forwards smile input to it, and layers the pre-game / HUD / game-over UI on top.
///
/// This is the only place that connects `FaceTrackingManager` (ARKit) to
/// `PinballScene` (SpriteKit) — the scene itself has no knowledge of ARKit.
struct PinballGameView: View {
    @ObservedObject var faceTrackingManager: FaceTrackingManager
    @ObservedObject var settings: SettingsStore
    @ObservedObject var scoreHistory: ScoreHistoryStore
    @StateObject private var gameState = GameState()
    @State private var scene: PinballScene?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let scene {
                    SpriteView(
                        scene: scene,
                        debugOptions: GameConfig.debugMode ? [.showsFPS, .showsPhysics, .showsNodeCount] : []
                    )
                    .ignoresSafeArea()
                }

                overlayContent

                if GameConfig.debugMode {
                    debugOverlay
                }
            }
            .onAppear {
                guard scene == nil, proxy.size.width > 0, proxy.size.height > 0 else { return }
                let newScene = PinballScene(size: proxy.size, gameState: gameState, settings: settings)
                newScene.scaleMode = .resizeFill
                scene = newScene
            }
        }
        .onChange(of: faceTrackingManager.smileState.isLeftSmileActive) { isActive in
            scene?.setLeftFlipperActive(isActive)
        }
        .onChange(of: faceTrackingManager.smileState.isRightSmileActive) { isActive in
            scene?.setRightFlipperActive(isActive)
        }
        .onChange(of: gameState.isGameOver) { isGameOver in
            guard isGameOver else { return }
            scoreHistory.record(gameState.score)
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch faceTrackingManager.phase {
        case .unsupported:
            EmptyView()
        case .waitingForFace:
            MessageCard(icon: "face.dashed", text: "顔をカメラの正面に合わせてください")
        case .calibrating:
            MessageCard(
                icon: "timer",
                text: "普通の表情で2秒間、\n正面を向いてください",
                progress: faceTrackingManager.calibrationProgress
            )
        case .ready:
            if gameState.isGameOver {
                GameOverCard(gameState: gameState) {
                    gameState.startNewGame()
                    scene?.startGame()
                }
            } else if gameState.isPlaying {
                VStack {
                    hud
                    Spacer()
                }
            } else {
                VStack {
                    ReadyToStartCard {
                        gameState.startNewGame()
                        scene?.startGame()
                    }
                    Spacer()
                }
            }
        }
    }

    private var hud: some View {
        VStack(spacing: 6) {
            HStack {
                scoreBlock(title: "SCORE", value: gameState.score, color: .white, alignment: .leading)
                Spacer()
                scoreBlock(title: "HIGH SCORE", value: gameState.highScore, color: .yellow, alignment: .trailing)
            }
            HStack {
                Text("BALL \(GameState.totalBalls - gameState.ballsRemaining + 1) / \(GameState.totalBalls)")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if !faceTrackingManager.isFaceDetected {
                    Label("顔を認識できません", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func scoreBlock(title: String, value: Int, color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(value)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: value)
        }
    }

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("mouthSmileLeft: \(String(format: "%.2f", faceTrackingManager.smileState.mouthSmileLeft))")
            Text("mouthSmileRight: \(String(format: "%.2f", faceTrackingManager.smileState.mouthSmileRight))")
            Text("baseline: \(String(format: "%.2f", faceTrackingManager.baselineLeft)) / \(String(format: "%.2f", faceTrackingManager.baselineRight))")
            Text("LEFT: \(faceTrackingManager.smileState.isLeftSmileActive ? "ON" : "OFF")  RIGHT: \(faceTrackingManager.smileState.isRightSmileActive ? "ON" : "OFF")")
            Text("FPS: \(String(format: "%.1f", faceTrackingManager.currentFPS))")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.green)
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(6)
    }
}

// MARK: - Overlay cards

private struct MessageCard: View {
    let icon: String
    let text: String
    var progress: Double?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.85))
            Text(text)
                .font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let progress {
                ProgressView(value: progress)
                    .tint(.yellow)
                    .frame(width: 160)
            }
        }
        .padding(28)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 40)
    }
}

private struct ReadyToStartCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("口角を上げてフリッパーを動かしてみよう")
                .font(.system(.subheadline, design: .rounded).bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Button(action: onStart) {
                Text("ゲームスタート")
                    .font(.system(.headline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

private struct GameOverCard: View {
    @ObservedObject var gameState: GameState
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("GAME OVER")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 2) {
                Text("SCORE")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(gameState.score)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 2) {
                Text("BEST")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(gameState.highScore)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.yellow)
            }

            Button(action: onRestart) {
                Text("もう一度遊ぶ")
                    .font(.system(.headline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 24)
        }
        .padding(28)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 32)
    }
}

#Preview {
    PinballGameView(faceTrackingManager: FaceTrackingManager(), settings: SettingsStore(), scoreHistory: ScoreHistoryStore())
}
