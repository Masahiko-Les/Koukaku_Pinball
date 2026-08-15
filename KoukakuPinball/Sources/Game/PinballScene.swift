import SpriteKit
import UIKit

/// A playable pinball table: rounded outer walls, a guided launch lane, three
/// bumpers, four targets, two slingshots, and two joint-driven flippers —
/// laid out so the ball reliably flows launch → top → center → flippers → back up.
///
/// This type has no knowledge of ARKit or face tracking — it only exposes
/// `setLeftFlipperActive` / `setRightFlipperActive`. `PinballGameView` is the sole
/// place that connects `FaceTrackingManager` output to these methods. Scoring and
/// ball-count state live in `GameState`, which also has no SpriteKit dependency.
final class PinballScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Layout fractions (relative to scene.size, so the table holds its
    // proportions from an iPhone SE up to the largest iPhone)

    private let laneWidthFraction: CGFloat = 0.13
    private let ballRadiusFraction: CGFloat = 0.022

    private let flipperLengthFraction: CGFloat = 0.21
    private let flipperThicknessFraction: CGFloat = 0.045
    private let flipperPivotYFraction: CGFloat = 0.16
    private let leftFlipperXFraction: CGFloat = 0.28
    private let rightFlipperXFraction: CGFloat = 0.72

    // MARK: - Flipper tuning

    private let flipperAngularSpeed: CGFloat = 56
    private let flipperMass: CGFloat = 1.2
    private let flipperRestDegrees: CGFloat = 25
    private let flipperUpDegrees: CGFloat = 32
    private var leftRestAngle: CGFloat { -flipperRestDegrees * .pi / 180 }
    private var rightRestAngle: CGFloat { flipperRestDegrees * .pi / 180 }
    private var swingAngle: CGFloat { (flipperRestDegrees + flipperUpDegrees) * .pi / 180 }

    // MARK: - Ball speed limits (points/sec), enforced every frame so the game never stalls or runs away

    private let minBallSpeed: CGFloat = 130
    private let maxBallSpeed: CGFloat = 1150

    // MARK: - Launch — set directly as velocity (not impulse) so it is independent of ball mass
    // and easy to reason about. Tuned generously: it is far better to overshoot into the
    // dome ceiling than to fall short and never reach the field.

    private let launchSpeed = CGVector(dx: -50, dy: 2200)
    /// Frames after launch during which the max-speed clamp (below) is suspended. Without
    /// this, `clampBallSpeed()` clips the launch velocity down to `maxBallSpeed` on the very
    /// next frame, silently undercutting the launch — which is exactly what was happening.
    private let launchGraceFrames = 40
    private var launchGraceFramesRemaining = 0

    // MARK: - Nodes

    private var leftFlipper: SKShapeNode!
    private var rightFlipper: SKShapeNode!
    private var ball: SKShapeNode!
    private var laneWidth: CGFloat = 0
    private var debugLabel: SKLabelNode?

    // MARK: - Input state (set by PinballGameView from FaceTrackingManager output)

    private var isLeftActive = false
    private var isRightActive = false

    // MARK: - Ball lifecycle

    private var isBallLaunched = false
    private var isHandlingBallLoss = false

    private let gameState: GameState
    private let settings: SettingsStore

    init(size: CGSize, gameState: GameState, settings: SettingsStore) {
        self.gameState = gameState
        self.settings = settings
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.09, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.2)
        physicsWorld.contactDelegate = self

        laneWidth = size.width * laneWidthFraction

        buildWalls()
        buildLaneVisual()
        buildLaunchGuide()
        buildDrainSensor()
        buildFlippers()
        buildOutLaneGuides()
        buildSlingshots()
        buildBumpers()
        buildTargets()
        spawnBall()

        if GameConfig.debugMode {
            buildDebugLabel()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        driveFlippers()
        clampBallSpeed()
        updateDebugLabel()
    }

    // MARK: - Public input

    func setLeftFlipperActive(_ active: Bool) {
        if active, !isLeftActive { GameSound.playFlipper(enabled: settings.isSoundEnabled) }
        isLeftActive = active
    }

    func setRightFlipperActive(_ active: Bool) {
        if active, !isRightActive { GameSound.playFlipper(enabled: settings.isSoundEnabled) }
        isRightActive = active
    }

    // MARK: - Game lifecycle

    /// Resets the board for a fresh game and fires the first ball. Safe to call again
    /// after a game over to restart.
    func startGame() {
        isHandlingBallLoss = false
        launchBall()
    }

    private var launchPosition: CGPoint {
        CGPoint(x: size.width * 0.91, y: size.height * 0.08)
    }

    private func launchBall() {
        ball.physicsBody?.isDynamic = true
        ball.position = launchPosition
        ball.physicsBody?.angularVelocity = 0
        ball.physicsBody?.velocity = launchSpeed
        isBallLaunched = true
        launchGraceFramesRemaining = launchGraceFrames
    }

    // MARK: - Per-frame flipper drive

    private func driveFlippers() {
        leftFlipper.physicsBody?.angularVelocity = isLeftActive ? flipperAngularSpeed : -flipperAngularSpeed
        rightFlipper.physicsBody?.angularVelocity = isRightActive ? -flipperAngularSpeed : flipperAngularSpeed
    }

    // MARK: - Ball speed clamping

    private func clampBallSpeed() {
        guard isBallLaunched, let body = ball.physicsBody else { return }

        let isInLaunchGrace = launchGraceFramesRemaining > 0
        if isInLaunchGrace {
            launchGraceFramesRemaining -= 1
        }

        let velocity = body.velocity
        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        guard speed > 1 else { return }
        if !isInLaunchGrace, speed > maxBallSpeed {
            let scale = maxBallSpeed / speed
            body.velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
        } else if speed < minBallSpeed {
            let scale = minBallSpeed / speed
            body.velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        for body in [contact.bodyA, contact.bodyB] {
            switch body.categoryBitMask {
            case PhysicsCategory.bumper:
                if let node = body.node as? SKShapeNode { handleBumperHit(node) }
            case PhysicsCategory.target:
                if let node = body.node as? SKShapeNode { handleTargetHit(node) }
            case PhysicsCategory.drain:
                handleBallLost()
            default:
                break
            }
        }
    }

    private func handleBumperHit(_ node: SKShapeNode) {
        gameState.addScore(100)
        pulse(node)
        GameSound.playBumper(enabled: settings.isSoundEnabled)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleTargetHit(_ node: SKShapeNode) {
        gameState.addScore(50)
        pulse(node)
        GameSound.playBumper(enabled: settings.isSoundEnabled)
    }

    private func handleBallLost() {
        guard isBallLaunched, !isHandlingBallLoss else { return }
        isHandlingBallLoss = true
        isBallLaunched = false
        ball.physicsBody?.velocity = .zero
        ball.physicsBody?.isDynamic = false
        ball.position = launchPosition

        GameSound.playBallLost(enabled: settings.isSoundEnabled)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        let isGameOver = gameState.loseBall()
        if !isGameOver {
            run(.sequence([
                .wait(forDuration: 1.0),
                .run { [weak self] in
                    self?.isHandlingBallLoss = false
                    self?.launchBall()
                }
            ]))
        }
    }

    private func pulse(_ node: SKShapeNode) {
        node.removeAction(forKey: "pulse")
        node.run(.sequence([.scale(to: 1.3, duration: 0.05), .scale(to: 1.0, duration: 0.15)]), withKey: "pulse")
    }

    // MARK: - Setup: walls

    private func buildWalls() {
        let w = size.width
        let h = size.height
        let cornerRadius = w * 0.16
        let leftWallBottomY = h * 0.07

        // One continuous open boundary: up the left wall, around the rounded top,
        // down the right wall (which doubles as the launch lane's outer wall) to y=0.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: leftWallBottomY))
        path.addLine(to: CGPoint(x: 0, y: h - cornerRadius))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: cornerRadius, y: h), radius: cornerRadius)
        path.addLine(to: CGPoint(x: w - cornerRadius, y: h))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w, y: h - cornerRadius), radius: cornerRadius)
        path.addLine(to: CGPoint(x: w, y: 0))

        let boardBody = SKPhysicsBody(edgeChainFrom: path)
        configureStatic(boardBody, category: PhysicsCategory.wall, restitution: 0.4, friction: 0.15)
        physicsBody = boardBody

        // Internal wall separating the launch lane from the main field. It stops short of
        // the launch guide (below) so a launched ball can cross over into the field.
        let laneX = w - laneWidth
        addStaticEdge(from: CGPoint(x: laneX, y: 0), to: CGPoint(x: laneX, y: h * 0.78), restitution: 0.15)
    }

    /// Faint tint over the launch lane so it visually reads as its own channel.
    private func buildLaneVisual() {
        let laneX = size.width - laneWidth
        let rect = CGRect(x: laneX, y: 0, width: laneWidth, height: size.height * 0.80)
        let node = SKShapeNode(rect: rect)
        node.fillColor = SKColor.white.withAlphaComponent(0.04)
        node.strokeColor = .clear
        node.zPosition = 1
        addChild(node)
    }

    /// The single most important piece of geometry on the table: a straight wall angled at
    /// ~45° spans the *entire* width of the launch lane near its top. A ball rocketing up the
    /// lane is guaranteed to hit it (it cannot slip past sideways), and hitting a 45°-ish
    /// surface converts most of that vertical speed into horizontal speed by simple reflection —
    /// so the ball reliably peels off to the left into the main field instead of just bouncing
    /// straight back down the lane.
    private func buildLaunchGuide() {
        let w = size.width
        let h = size.height
        let baseY = h * 0.78
        let span = laneWidth * 1.9
        let angle: CGFloat = 48 * .pi / 180

        let start = CGPoint(x: w, y: baseY)
        let end = CGPoint(x: w - span, y: baseY + span * tan(angle))

        let body = SKPhysicsBody(edgeFrom: start, to: end)
        configureStatic(body, category: PhysicsCategory.wall, restitution: 0.35, friction: 0.05)
        let node = SKNode()
        node.physicsBody = body
        addChild(node)

        // Thin visible guide so the deflection is legible, not an invisible wall.
        let visualPath = CGMutablePath()
        visualPath.move(to: start)
        visualPath.addLine(to: end)
        let visual = SKShapeNode(path: visualPath)
        visual.strokeColor = SKColor.white.withAlphaComponent(0.35)
        visual.lineWidth = 3
        visual.zPosition = 2
        addChild(visual)
    }

    private func addStaticEdge(from a: CGPoint, to b: CGPoint, restitution: CGFloat) {
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        configureStatic(body, category: PhysicsCategory.wall, restitution: restitution, friction: 0.1)
        let node = SKNode()
        node.physicsBody = body
        addChild(node)
    }

    private func configureStatic(_ body: SKPhysicsBody, category: UInt32, restitution: CGFloat, friction: CGFloat) {
        body.categoryBitMask = category
        body.restitution = restitution
        body.friction = friction
    }

    // MARK: - Setup: drain sensor

    private func buildDrainSensor() {
        // Spans the full width (including under the lane) so a ball can never fall through
        // uncaught, regardless of which path it took to get below the playfield.
        let body = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 2), to: CGPoint(x: size.width, y: 2))
        body.categoryBitMask = PhysicsCategory.drain
        body.collisionBitMask = PhysicsCategory.none
        let node = SKNode()
        node.physicsBody = body
        addChild(node)
    }

    // MARK: - Setup: flippers

    private func buildFlippers() {
        let pivotY = size.height * flipperPivotYFraction
        let length = size.width * flipperLengthFraction
        let thickness = size.width * flipperThicknessFraction
        let leftPivot = CGPoint(x: size.width * leftFlipperXFraction, y: pivotY)
        let rightPivot = CGPoint(x: size.width * rightFlipperXFraction, y: pivotY)

        leftFlipper = makeFlipperNode(pivot: leftPivot, length: length, thickness: thickness, direction: 1)
        leftFlipper.zRotation = leftRestAngle
        addChild(leftFlipper)
        pinFlipper(leftFlipper, at: leftPivot, lowerLimit: 0, upperLimit: swingAngle)

        rightFlipper = makeFlipperNode(pivot: rightPivot, length: length, thickness: thickness, direction: -1)
        rightFlipper.zRotation = rightRestAngle
        addChild(rightFlipper)
        pinFlipper(rightFlipper, at: rightPivot, lowerLimit: -swingAngle, upperLimit: 0)
    }

    /// `direction` is +1 for a flipper whose paddle extends toward +x from its pivot (left
    /// flipper, reaching toward table center) or -1 for one extending toward -x (right, mirrored).
    private func makeFlipperNode(pivot: CGPoint, length: CGFloat, thickness: CGFloat, direction: CGFloat) -> SKShapeNode {
        let signedLength = length * direction
        let rect = CGRect(x: min(0, signedLength), y: -thickness / 2, width: abs(signedLength), height: thickness)
        let path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)

        let node = SKShapeNode(path: path)
        node.fillColor = .white
        node.strokeColor = .clear
        node.position = pivot
        node.zPosition = 10

        let body = SKPhysicsBody(rectangleOf: CGSize(width: abs(signedLength), height: thickness), center: CGPoint(x: signedLength / 2, y: 0))
        body.isDynamic = true
        body.affectedByGravity = false
        body.restitution = 0.6
        body.friction = 0.2
        body.linearDamping = 0
        body.angularDamping = 0
        body.mass = flipperMass
        body.categoryBitMask = PhysicsCategory.flipper
        // Flippers nearly touch at rest; excluding their own category stops the joint solver
        // from deadlocking against itself while still colliding normally with everything else.
        body.collisionBitMask = ~PhysicsCategory.flipper
        body.usesPreciseCollisionDetection = true
        node.physicsBody = body

        return node
    }

    /// Pins `flipper` to the (static) scene body at `point`. The angle limits are relative to
    /// the flipper's rotation at the moment the joint is created (its rest pose), not absolute.
    private func pinFlipper(_ flipper: SKShapeNode, at point: CGPoint, lowerLimit: CGFloat, upperLimit: CGFloat) {
        guard let flipperBody = flipper.physicsBody, let anchorBody = physicsBody else { return }
        let joint = SKPhysicsJointPin.joint(withBodyA: anchorBody, bodyB: flipperBody, anchor: point)
        joint.shouldEnableLimits = true
        joint.lowerAngleLimit = lowerLimit
        joint.upperAngleLimit = upperLimit
        physicsWorld.add(joint)
    }

    // MARK: - Setup: out-lane guides

    /// Short angled rails just outside each flipper, giving the sides a defined channel
    /// instead of a fully open edge — visually and physically an "out lane."
    private func buildOutLaneGuides() {
        let w = size.width
        let h = size.height

        addStaticEdge(
            from: CGPoint(x: w * 0.10, y: h * 0.30),
            to: CGPoint(x: w * 0.17, y: h * 0.06),
            restitution: 0.3
        )
        addStaticEdge(
            from: CGPoint(x: w * 0.90, y: h * 0.30),
            to: CGPoint(x: w * 0.83, y: h * 0.06),
            restitution: 0.3
        )
    }

    // MARK: - Setup: slingshots

    private func buildSlingshots() {
        let leftAnchor = CGPoint(x: size.width * 0.29, y: size.height * 0.28)
        addSlingshot(at: leftAnchor, mirrored: false)

        let rightAnchor = CGPoint(x: size.width * 0.71, y: size.height * 0.28)
        addSlingshot(at: rightAnchor, mirrored: true)
    }

    private func addSlingshot(at anchor: CGPoint, mirrored: Bool) {
        let width = size.width * 0.11
        let height = size.height * 0.08
        let sign: CGFloat = mirrored ? -1 : 1

        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: sign * width, y: height * 0.30))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.fillColor = SKColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 0.9)
        node.strokeColor = .clear
        node.position = anchor
        node.zPosition = 4

        let body = SKPhysicsBody(polygonFrom: path)
        body.isDynamic = false
        body.restitution = 1.0
        body.friction = 0.1
        body.categoryBitMask = PhysicsCategory.slingshot
        node.physicsBody = body

        addChild(node)
    }

    // MARK: - Setup: bumpers (top 30% — a tight triangle so the ball can ping between them)

    private func buildBumpers() {
        let radius = size.width * 0.062
        let positions: [(CGPoint, SKColor)] = [
            (CGPoint(x: size.width * 0.50, y: size.height * 0.78), SKColor(red: 0.55, green: 0.35, blue: 1.0, alpha: 1)),
            (CGPoint(x: size.width * 0.34, y: size.height * 0.67), SKColor(red: 1.0, green: 0.25, blue: 0.35, alpha: 1)),
            (CGPoint(x: size.width * 0.66, y: size.height * 0.67), SKColor(red: 1.0, green: 0.55, blue: 0.85, alpha: 1))
        ]
        for (position, color) in positions {
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = color
            node.strokeColor = SKColor.white.withAlphaComponent(0.6)
            node.lineWidth = 2
            node.position = position
            node.zPosition = 6

            let body = SKPhysicsBody(circleOfRadius: radius)
            body.isDynamic = false
            body.restitution = 1.25
            body.categoryBitMask = PhysicsCategory.bumper
            node.physicsBody = body

            addChild(node)
        }
    }

    // MARK: - Setup: targets (middle 40% — placed where balls falling from the bumpers actually pass)

    private func buildTargets() {
        let targetSize = CGSize(width: size.width * 0.03, height: size.height * 0.05)
        let positions: [CGPoint] = [
            CGPoint(x: size.width * 0.20, y: size.height * 0.56),
            CGPoint(x: size.width * 0.23, y: size.height * 0.43),
            CGPoint(x: size.width * 0.80, y: size.height * 0.56),
            CGPoint(x: size.width * 0.77, y: size.height * 0.43)
        ]
        for position in positions {
            let node = SKShapeNode(rectOf: targetSize, cornerRadius: targetSize.width / 2)
            node.fillColor = SKColor(red: 0.25, green: 0.95, blue: 0.85, alpha: 1)
            node.strokeColor = .clear
            node.position = position
            node.zPosition = 6

            let body = SKPhysicsBody(rectangleOf: targetSize)
            body.isDynamic = false
            body.restitution = 0.6
            body.categoryBitMask = PhysicsCategory.target
            node.physicsBody = body

            addChild(node)
        }
    }

    // MARK: - Setup: ball

    private func spawnBall() {
        let radius = size.width * ballRadiusFraction
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = SKColor(red: 1.0, green: 0.72, blue: 0.2, alpha: 1)
        node.strokeColor = SKColor.white.withAlphaComponent(0.6)
        node.lineWidth = 1
        node.zPosition = 20

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.restitution = 0.5
        body.friction = 0.1
        body.linearDamping = 0.02
        body.angularDamping = 0.1
        body.mass = 0.08
        body.categoryBitMask = PhysicsCategory.ball
        body.contactTestBitMask = PhysicsCategory.bumper | PhysicsCategory.target | PhysicsCategory.drain
        body.usesPreciseCollisionDetection = true
        // Parked (no gravity/motion) until `launchBall()` fires it — there is no floor under
        // the lane, so an un-parked ball would immediately fall through the drain sensor.
        body.isDynamic = false
        node.physicsBody = body

        addChild(node)
        ball = node
        ball.position = launchPosition
    }

    // MARK: - Debug

    private func buildDebugLabel() {
        let label = SKLabelNode(fontNamed: "Menlo")
        label.fontSize = 12
        label.fontColor = .green
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 8, y: size.height - 8)
        label.zPosition = 100
        addChild(label)
        debugLabel = label
    }

    private func updateDebugLabel() {
        guard GameConfig.debugMode, let debugLabel, let velocity = ball.physicsBody?.velocity else { return }
        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        debugLabel.text = String(format: "ball speed: %.0f pt/s  y: %.0f%%", speed, 100 * ball.position.y / size.height)
    }
}
