import SwiftUI

/// Sound on/off. The hardware silent switch doesn't reliably mute this app's
/// effects while ARKit's camera session is active, so this gives a guaranteed way
/// to turn sound off regardless of that switch.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var faceTrackingManager: FaceTrackingManager
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("サウンド", isOn: $settings.isSoundEnabled)
                } footer: {
                    Text("フリッパー・バンパー・ボールロスト時の効果音のオン/オフを切り替えます。")
                }

                Section {
                    Button("口角を登録し直す") {
                        faceTrackingManager.recalibrate()
                        selectedTab = .faceCheck
                    }
                } footer: {
                    Text("口角の反応がズレていると感じたら、こちらから登録し直せます。「口角チェック」タブに切り替わり、キャリブレーションが再度始まります。")
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView(settings: SettingsStore(), faceTrackingManager: FaceTrackingManager(), selectedTab: .constant(.settings))
}
