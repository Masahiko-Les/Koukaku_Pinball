import Foundation

/// Identifies each tab in the root `TabView`, so other screens can request a
/// programmatic switch (e.g. Settings' recalibrate button jumping to 口角チェック).
enum AppTab: Hashable {
    case faceCheck
    case pinball
    case history
    case settings
}
