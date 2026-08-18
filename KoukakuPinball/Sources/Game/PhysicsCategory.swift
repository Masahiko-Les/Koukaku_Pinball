import Foundation

/// Bitmask categories for `SKPhysicsBody.categoryBitMask` / `collisionBitMask` / `contactTestBitMask`.
enum PhysicsCategory {
    static let none: UInt32 = 0
    static let ball: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let bumper: UInt32 = 1 << 2
    static let flipper: UInt32 = 1 << 3
    /// Sensor spanning the bottom of the board. Touching it means the ball has gone past the
    /// flippers for good; it has no collision shape of its own, just a contact trigger.
    static let drain: UInt32 = 1 << 4
    static let all: UInt32 = .max
}
