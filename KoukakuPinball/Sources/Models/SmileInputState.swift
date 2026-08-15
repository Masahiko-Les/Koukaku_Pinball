import Foundation

/// Snapshot of ARKit mouth blend shapes and the derived digital input state.
/// Contains no ARKit or SwiftUI dependency so it can be handed directly to
/// future game logic (e.g. SpriteKit flippers).
struct SmileInputState: Equatable {
    var mouthSmileLeft: Float = 0
    var mouthSmileRight: Float = 0
    var mouthFrownLeft: Float = 0
    var mouthFrownRight: Float = 0

    var isLeftSmileActive: Bool = false
    var isRightSmileActive: Bool = false
}
