import Foundation

/// Score, high score, and ball-count state for one play session.
///
/// Has no ARKit or SpriteKit dependency: `PinballScene` reports events into it
/// (`addScore`, `loseBall`), and SwiftUI observes it directly to drive the HUD.
final class GameState: ObservableObject {
    static let totalBalls = 3

    @Published private(set) var score: Int = 0
    @Published private(set) var highScore: Int
    @Published private(set) var ballsRemaining: Int = GameState.totalBalls
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isGameOver: Bool = false
    @Published private(set) var isPaused: Bool = false

    private let highScoreKey = "com.mfujita.koukakupinball.highScore"

    init() {
        highScore = UserDefaults.standard.integer(forKey: highScoreKey)
    }

    func startNewGame() {
        score = 0
        ballsRemaining = Self.totalBalls
        isPlaying = true
        isGameOver = false
        isPaused = false
    }

    /// Only meaningful mid-game — tapping the screen before or after a game has no effect.
    func togglePause() {
        guard isPlaying else { return }
        isPaused.toggle()
    }

    /// Quits the current game without recording a score-history entry — used by "ゲームを
    /// 終了する" on the pause screen. Unlike losing all three balls, this returns straight to
    /// the pre-game "ゲームスタート" state rather than showing GAME OVER.
    func abandonGame() {
        guard isPlaying else { return }
        score = 0
        ballsRemaining = Self.totalBalls
        isPlaying = false
        isGameOver = false
        isPaused = false
    }

    func addScore(_ points: Int) {
        guard isPlaying else { return }
        score += points
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: highScoreKey)
        }
    }

    /// Call when the ball drains. Returns `true` if that was the last ball (game just ended).
    @discardableResult
    func loseBall() -> Bool {
        guard isPlaying else { return false }
        ballsRemaining -= 1
        guard ballsRemaining <= 0 else { return false }
        isPlaying = false
        isGameOver = true
        return true
    }
}
