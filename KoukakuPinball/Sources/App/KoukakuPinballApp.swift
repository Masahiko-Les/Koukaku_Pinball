import SwiftUI
import UIKit

@main
struct KoukakuPinballApp: App {
    init() {
        // Without this, a tab whose content extends under the safe area (PinballGameView's
        // full-bleed SpriteView, via .ignoresSafeArea()) can make the native tab bar render
        // only the selected tab's icon+label while the other three vanish — a known
        // SwiftUI/UIKit inconsistency between the tab bar's "standard" and "scroll edge"
        // appearances. Forcing them to match keeps all four items rendering consistently.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
