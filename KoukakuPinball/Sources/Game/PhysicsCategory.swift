import Foundation

/// Bitmask categories for `SKPhysicsBody.categoryBitMask` / `collisionBitMask` / `contactTestBitMask`.
enum PhysicsCategory {
    static let none: UInt32 = 0
    static let ball: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let bumper: UInt32 = 1 << 2
    static let flipper: UInt32 = 1 << 3
    static let target: UInt32 = 1 << 4
    static let drain: UInt32 = 1 << 5
    static let slingshot: UInt32 = 1 << 6
    static let all: UInt32 = .max
}
