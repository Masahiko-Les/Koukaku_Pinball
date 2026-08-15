import SwiftUI

/// Sound on/off. The hardware silent switch doesn't reliably mute this app's
/// effects while ARKit's camera session is active, so this gives a guaranteed way
/// to turn sound off regardless of that switch.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("サウンド", isOn: $settings.isSoundEnabled)
                } footer: {
                    Text("フリッパー・バンパー・ボールロスト時の効果音のオン/オフを切り替えます。")
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView(settings: SettingsStore())
}
