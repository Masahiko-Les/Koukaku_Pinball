import SpriteKit
import UIKit

/// A playable pinball table: a cream, rounded-card-style board with six scattered
/// star bumpers, a guided launch lane, and two joint-driven flippers. A ball that
/// falls past the flippers is caught by a sensor and teleported back to the launch
/// pad for an automatic relaunch.
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
    /// Distance from `playfieldCenterX` to each flipper's pivot, as a fraction of scene width.
    /// Both flippers derive their position from this one value, so they're always exact mirror
    /// images of each other rather than two independently-tuned magic numbers.
    private let flipperOffsetFraction: CGFloat = 0.22

    /// The horizontal center of the *main playfield* — excluding the launch lane, which is an
    /// independent structure on the right and isn't part of the mirror symmetry. Everything in
    /// the flipper/return-lane region is positioned as `playfieldCenterX ± offset`.
    private var playfieldCenterX: CGFloat { (size.width - laneWidth) / 2 }

    // MARK: - Flipper tuning

    // Doubled from 56 at the user's request — flipper shots were only reaching about half
    // the board's height.
    private let flipperAngularSpeed: CGFloat = 112
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

    private let baseLaunchSpeed = CGVector(dx: -50, dy: 2200)
    /// Small per-launch randomization so the ball doesn't take the exact same path every
    /// time. Kept narrow relative to `baseLaunchSpeed` so the launch stays reliable.
    private let launchSpeedJitterX: ClosedRange<CGFloat> = -15...15
    private let launchSpeedJitterY: ClosedRange<CGFloat> = -90...90
    /// Frames after launch during which the max-speed clamp (below) is suspended. Without
    /// this, `clampBallSpeed()` clips the launch velocity down to `maxBallSpeed` on the very
    /// next frame, silently undercutting the launch — which is exactly what was happening.
    private let launchGraceFrames = 40
    private var launchGraceFramesRemaining = 0

    /// How long the ball stays "lost" (frozen at the launch pad) before automatically firing
    /// again, after falling past the flippers.
    private let ballLostRelaunchDelay: TimeInterval = 1.0

    /// Safety net: a very fast ball can occasionally tunnel through a thin edge-based wall (or
    /// skip past the drain sensor) in a single physics step and end up outside the board
    /// entirely, off to a side or falling forever below the bottom. If the ball stays outside
    /// the board's bounds for this many frames (~3s at 60fps), it's treated as lost and
    /// returned to the launch pad, regardless of which edge it escaped through.
    private let offScreenRecoveryFrames = 180
    private var offScreenFrameCount = 0

    // MARK: - Colors

    private let boardBackgroundColor = SKColor(red: 0.96, green: 0.91, blue: 0.83, alpha: 1)
    private let boardOutlineColor = SKColor(red: 0.28, green: 0.19, blue: 0.13, alpha: 1)
    private let flipperColor = SKColor(red: 0.87, green: 0.27, blue: 0.24, alpha: 1)

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

    /// True once the currently-launched ball has confirmed made it into the main field.
    /// Once true, `laneGateNode` seals the top of the lane so the ball can't wander back
    /// in after bouncing off a bumper — only the *next* launch (via `launchBall()`) reopens it.
    private var hasEnteredFieldThisLaunch = false
    private var laneGateNode: SKNode?

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
        backgroundColor = boardBackgroundColor
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.2)
        physicsWorld.contactDelegate = self

        laneWidth = size.width * laneWidthFraction

        buildWalls()
        buildLaunchGuide()
        buildDrainSensor()
        buildFlippers()
        buildReturnLanes()
        buildBumpers()
        spawnBall()

        if GameConfig.debugMode {
            buildDebugLabel()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        driveFlippers()
        clampBallSpeed()
        checkForFieldEntry()
        checkForOffScreenBall()
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
        laneGateNode?.removeFromParent()
        laneGateNode = nil
        hasEnteredFieldThisLaunch = false
        offScreenFrameCount = 0

        ball.physicsBody?.isDynamic = true
        ball.position = launchPosition
        ball.physicsBody?.angularVelocity = 0
        ball.physicsBody?.velocity = CGVector(
            dx: baseLaunchSpeed.dx + CGFloat.random(in: launchSpeedJitterX),
            dy: baseLaunchSpeed.dy + CGFloat.random(in: launchSpeedJitterY)
        )
        isBallLaunched = true
        launchGraceFramesRemaining = launchGraceFrames
    }

    /// The gap at the top of the lane (above the separator wall) has to stay open so a
    /// launched ball can cross into the field — but that same gap lets a ball that's already
    /// in play wander back into the lane after bouncing off a bumper, sliding all the way back
    /// down to the launch pad. Once this ball has genuinely made it into the field, seal that
    /// gap with a one-shot wall so it can only be reopened by the next `launchBall()`.
    private func checkForFieldEntry() {
        guard isBallLaunched, !hasEnteredFieldThisLaunch else { return }
        let laneX = size.width - laneWidth
        guard ball.position.x < laneX - size.width * 0.03 else { return }

        hasEnteredFieldThisLaunch = true
        let body = SKPhysicsBody(edgeFrom: CGPoint(x: laneX, y: size.height * 0.86), to: CGPoint(x: laneX, y: size.height))
        body.categoryBitMask = PhysicsCategory.wall
        body.restitution = 0.3
        body.friction = 0.1
        let node = SKNode()
        node.physicsBody = body
        addChild(node)
        laneGateNode = node
    }

    /// See `offScreenRecoveryFrames`. Checked every frame; resets the streak the instant the
    /// ball is back within bounds, so only a *sustained* escape triggers a recovery.
    private func checkForOffScreenBall() {
        guard isBallLaunched else {
            offScreenFrameCount = 0
            return
        }

        let margin: CGFloat = 4
        let isOffScreen = ball.position.x < -margin
            || ball.position.x > size.width + margin
            || ball.position.y < -margin

        offScreenFrameCount = isOffScreen ? offScreenFrameCount + 1 : 0
        guard offScreenFrameCount >= offScreenRecoveryFrames else { return }
        offScreenFrameCount = 0
        handleBallLost()
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

    /// Fired the instant the ball touches the bottom sensor — i.e. the moment it's gone past
    /// the flippers for good. Teleports it back to the launch pad and, after a brief pause,
    /// fires it again automatically (unless that was the last ball).
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
                .wait(forDuration: ballLostRelaunchDelay),
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
        // Stops where the return lanes begin (buildReturnLanes()), so the ball is handed off
        // with no gap to slip through. Matches the lane separator's bottom below for a simple,
        // consistent hand-off height on both sides.
        let leftWallBottomY = h * 0.30

        // One continuous open boundary: up the (square-cornered) left wall, around the
        // top-right corner (a cycloid curve), down the right wall (the launch lane's outer
        // wall) to y=0. The top-left corner is intentionally left square to match the
        // reference design. The lane's bottom (below the return lanes) stays open so the
        // ball can fall through to the drain sensor.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: leftWallBottomY))
        path.addLine(to: CGPoint(x: 0, y: h))
        let cornerPoints = cornerCycloidPoints(radius: w * 0.11, segments: 20)
        path.addLine(to: cornerPoints[0])
        for point in cornerPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: w, y: 0))

        let boardBody = SKPhysicsBody(edgeChainFrom: path)
        configureStatic(boardBody, category: PhysicsCategory.wall, restitution: 0.4, friction: 0.15)
        physicsBody = boardBody

        // Visible outline tracing the same path, since the physics edge alone is invisible.
        let outline = SKShapeNode(path: path)
        outline.strokeColor = boardOutlineColor
        outline.lineWidth = max(3, w * 0.012)
        outline.lineCap = .round
        outline.zPosition = 3
        addChild(outline)

        // Internal wall separating the launch lane from the main field: a single straight line.
        // It stops short of the launch guide (above, matching its height) so a launched ball
        // can cross over into the field, and stops at the same height as the left wall (below)
        // where the return lanes take over.
        let laneX = w - laneWidth
        addStaticEdge(from: CGPoint(x: laneX, y: h * 0.30), to: CGPoint(x: laneX, y: h * 0.86), restitution: 0.15, visible: true)
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
        // Raised from 0.78 so the ball can travel further up the (outer) lane wall before
        // it's forced to deflect — it was hitting this wall's near end well before ever
        // reaching the top-right cycloid corner (radius 0.11w, so it starts around h*0.90).
        // Kept a little below that so this guide doesn't overlap the corner's own geometry.
        let baseY = h * 0.86
        let span = laneWidth * 1.9
        let angle: CGFloat = 48 * .pi / 180

        let start = CGPoint(x: w, y: baseY)
        let end = CGPoint(x: w - span, y: baseY + span * tan(angle))

        // Physics only — no visible line. This wall's job is purely functional (redirecting
        // an ascending ball into the field); drawing it reads as a stray diagonal slash.
        addStaticEdge(from: start, to: end, restitution: 0.35, visible: false)
    }

    private func addStaticEdge(from a: CGPoint, to b: CGPoint, restitution: CGFloat, visible: Bool = false) {
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        configureStatic(body, category: PhysicsCategory.wall, restitution: restitution, friction: 0.1)
        let node = SKNode()
        node.physicsBody = body
        addChild(node)

        guard visible else { return }
        let visualPath = CGMutablePath()
        visualPath.move(to: a)
        visualPath.addLine(to: b)
        let visual = SKShapeNode(path: visualPath)
        visual.strokeColor = boardOutlineColor.withAlphaComponent(0.5)
        visual.lineWidth = 2.5
        visual.zPosition = 2
        addChild(visual)
    }

    private func configureStatic(_ body: SKPhysicsBody, category: UInt32, restitution: CGFloat, friction: CGFloat) {
        body.categoryBitMask = category
        body.restitution = restitution
        body.friction = friction
    }

    // MARK: - Setup: drain sensor

    private func buildDrainSensor() {
        // Spans the full width (including under the lane) so a ball can never fall through
        // uncaught, regardless of which path it took to get below the playfield. Sensor
        // only — no collision shape — so it doesn't interfere with anything physically.
        let body = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 2), to: CGPoint(x: size.width, y: 2))
        body.categoryBitMask = PhysicsCategory.drain
        body.collisionBitMask = PhysicsCategory.none
        let node = SKNode()
        node.physicsBody = body
        addChild(node)
    }

    /// Samples a cycloid — the path traced by a point on a circle of `radius` rolling along
    /// a line — for a half turn (θ: 0...π), mirrored on both axes for the top-right corner:
    /// it runs from the top edge (horizontal tangent) down into the right wall (vertical
    /// tangent) — a curved fillet rather than a circular arc. Ordered start-to-end
    /// (top edge → right wall).
    private func cornerCycloidPoints(radius: CGFloat, segments: Int) -> [CGPoint] {
        let w = size.width
        let h = size.height
        let verticalExtent = 2 * radius
        let points = (0...segments).map { step -> CGPoint in
            let theta = CGFloat(step) / CGFloat(segments) * CGFloat.pi
            let x = w - radius * (theta - sin(theta))
            let y = (h - verticalExtent) + radius * (1 - cos(theta))
            return CGPoint(x: x, y: y)
        }
        return points.reversed()
    }

    // MARK: - Setup: flippers

    private func buildFlippers() {
        let pivotY = size.height * flipperPivotYFraction
        let length = size.width * flipperLengthFraction
        let thickness = size.width * flipperThicknessFraction
        let offset = size.width * flipperOffsetFraction
        let leftPivot = CGPoint(x: playfieldCenterX - offset, y: pivotY)
        let rightPivot = CGPoint(x: playfieldCenterX + offset, y: pivotY)

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
        node.fillColor = flipperColor
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

    // MARK: - Setup: return lanes

    /// Classic pinball "flipper lane" / "return lane": rather than an out-lane that drains
    /// unrecoverably, a ball drifting down the outside of either flipper is caught by an
    /// angled deflector and redirected back in toward that flipper, so falling wide is a
    /// save opportunity rather than an automatic, do-nothing loss. Each deflector starts
    /// exactly where the adjacent wall stops (the left board wall / the lane separator), so
    /// there's no gap for the ball to slip past.
    ///
    /// The end points are kept clear of the flippers themselves — 0.05w out from the pivot
    /// horizontally, 0.05h above the pivot height vertically — rather than reaching onto them
    /// directly. A flipper's *dynamic* body sweeping through a *static* deflector that overlaps
    /// it causes constant low-level interpenetration, which the physics engine "resolves" every
    /// frame by injecting energy — seen as the ball climbing walls or bouncing on its own with
    /// no flipper input. Even at full deflection the flipper's near corner only reaches about
    /// 0.012w/0.019h past its pivot (it swings within a ~57° arc that stays on the flipper's own
    /// side), so this margin stays a comfortable few times larger than that. Leaving a small gap
    /// and letting gravity carry the ball the last bit onto the flipper avoids overlap entirely.
    private func buildReturnLanes() {
        let w = size.width
        let h = size.height
        let offset = w * flipperOffsetFraction
        let leftFlipperPivotX = playfieldCenterX - offset
        let rightFlipperPivotX = playfieldCenterX + offset
        let laneX = w - laneWidth
        let endY = size.height * flipperPivotYFraction + h * 0.05
        // Extends each guide further along its own line, past the clearance-based end point
        // computed above, at the user's request to reach closer to the flipper's base
        // (originally +10%, then another +10% on top of that, for +20% total).
        let lengthMultiplier: CGFloat = 1.20

        let leftStart = CGPoint(x: 0, y: h * 0.30)
        let leftEnd = extended(from: leftStart, to: CGPoint(x: leftFlipperPivotX - w * 0.05, y: endY), by: lengthMultiplier)
        addStaticEdge(from: leftStart, to: leftEnd, restitution: 0.3, visible: true)

        let rightStart = CGPoint(x: laneX, y: h * 0.30)
        let rightEnd = extended(from: rightStart, to: CGPoint(x: rightFlipperPivotX + w * 0.05, y: endY), by: lengthMultiplier)
        addStaticEdge(from: rightStart, to: rightEnd, restitution: 0.3, visible: true)
    }

    private func extended(from start: CGPoint, to end: CGPoint, by multiplier: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * multiplier, y: start.y + (end.y - start.y) * multiplier)
    }

    // MARK: - Setup: bumpers — six, scattered top-to-mid-field rather than tightly clustered

    private func buildBumpers() {
        let radius = size.width * 0.05
        let positions: [(CGPoint, SKColor)] = [
            (CGPoint(x: size.width * 0.22, y: size.height * 0.87), SKColor(red: 0.93, green: 0.42, blue: 0.42, alpha: 1)),
            (CGPoint(x: size.width * 0.65, y: size.height * 0.78), SKColor(red: 0.30, green: 0.75, blue: 0.78, alpha: 1)),
            (CGPoint(x: size.width * 0.40, y: size.height * 0.68), SKColor(red: 0.96, green: 0.75, blue: 0.25, alpha: 1)),
            (CGPoint(x: size.width * 0.62, y: size.height * 0.56), SKColor(red: 0.55, green: 0.78, blue: 0.45, alpha: 1)),
            (CGPoint(x: size.width * 0.22, y: size.height * 0.52), SKColor(red: 0.40, green: 0.68, blue: 0.90, alpha: 1)),
            (CGPoint(x: size.width * 0.47, y: size.height * 0.40), SKColor(red: 0.75, green: 0.48, blue: 0.80, alpha: 1))
        ]
        for (position, color) in positions {
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = color
            node.strokeColor = SKColor.white.withAlphaComponent(0.8)
            node.lineWidth = 2
            node.position = position
            node.zPosition = 6

            let star = SKLabelNode(text: "★")
            star.fontSize = radius * 1.1
            star.fontColor = SKColor.white.withAlphaComponent(0.9)
            star.verticalAlignmentMode = .center
            star.horizontalAlignmentMode = .center
            star.zPosition = 1
            node.addChild(star)

            let body = SKPhysicsBody(circleOfRadius: radius)
            body.isDynamic = false
            body.restitution = 1.25
            body.categoryBitMask = PhysicsCategory.bumper
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
        body.contactTestBitMask = PhysicsCategory.bumper | PhysicsCategory.drain
        body.usesPreciseCollisionDetection = true
        // Parked (no gravity/motion) until `launchBall()` fires it — there is no floor under
        // the lane, so an un-parked ball would immediately fall through to the drain sensor.
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
        label.fontColor = .red
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
        debugLabel.text = String(format: "speed: %.0f pt/s  y: %.0f%%", speed, 100 * ball.position.y / size.height)
    }
}
