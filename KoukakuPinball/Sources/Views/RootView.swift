import SwiftUI

/// Owns the single `FaceTrackingManager` shared by every tab, so calibration
/// state and the AR session survive switching between the debug screen and the game.
struct RootView: View {
    @StateObject private var faceTrackingManager = FaceTrackingManager()
    @StateObject private var settings = SettingsStore()
    @StateObject private var scoreHistory = ScoreHistoryStore()

    @State private var selectedTab: AppTab = .faceCheck

    var body: some View {
        Group {
            if faceTrackingManager.isSupported {
                TabView(selection: $selectedTab) {
                    ContentView(faceTrackingManager: faceTrackingManager)
                        .tabItem { Label("口角チェック", systemImage: "face.smiling") }
                        .tag(AppTab.faceCheck)

                    PinballGameView(
                        faceTrackingManager: faceTrackingManager,
                        settings: settings,
                        scoreHistory: scoreHistory
                    )
                        .tabItem { Label("ピンボール", systemImage: "circle.grid.2x2") }
                        .tag(AppTab.pinball)

                    ScoreHistoryView(scoreHistory: scoreHistory)
                        .tabItem { Label("履歴", systemImage: "list.bullet.clipboard") }
                        .tag(AppTab.history)

                    SettingsView(settings: settings, faceTrackingManager: faceTrackingManager, selectedTab: $selectedTab)
                        .tabItem { Label("設定", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            } else {
                unsupportedView
            }
        }
        .onAppear { faceTrackingManager.start() }
        .onDisappear { faceTrackingManager.pause() }
    }

    private var unsupportedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("この端末は顔認識機能に対応していません")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    RootView()
}
