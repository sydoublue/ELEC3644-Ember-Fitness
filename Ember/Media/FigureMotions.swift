import CoreGraphics

/// A stick-figure pose described by joint angles (degrees).
/// Direction convention: 0° = up, 90° = right, 180° = down, 270° = left. Side views face right.
/// "N" = near limb (drawn solid), "F" = far limb (drawn faded). In front views N is screen-right.
struct FigurePose {
    enum Anchor { case hip, footN, footF, handN, elbowN, kneeN }

    var torso: Double = 0, head: Double = 0
    var uaN: Double = 180, faN: Double = 180, uaF: Double = 180, faF: Double = 180
    var thN: Double = 180, shN: Double = 180, thF: Double = 180, shF: Double = 180
    /// Shoulder / hip width — 0 for side views.
    var sw: Double = 0, hw: Double = 0
    var anchor: Anchor = .footN
    var ax: Double = 0.5, ay: Double = FigureMotion.ground

    func lerp(to b: FigurePose, _ t: Double) -> FigurePose {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var p = self
        p.torso = m(torso, b.torso); p.head = m(head, b.head)
        p.uaN = m(uaN, b.uaN); p.faN = m(faN, b.faN); p.uaF = m(uaF, b.uaF); p.faF = m(faF, b.faF)
        p.thN = m(thN, b.thN); p.shN = m(shN, b.shN); p.thF = m(thF, b.thF); p.shF = m(shF, b.shF)
        p.sw = m(sw, b.sw); p.hw = m(hw, b.hw)
        p.ax = m(ax, b.ax); p.ay = m(ay, b.ay)
        return p
    }
}

/// Joint positions in a unit square (0...1, y down).
struct FigureJoints {
    var hip, shoulderC, shoulderN, shoulderF, hipN, hipF, neck, head: CGPoint
    var elbowN, handN, elbowF, handF, kneeN, footN, kneeF, footF: CGPoint
}

enum FigureLengths {
    static let torso = 0.27, neck = 0.07, head = 0.058
    static let upperArm = 0.14, forearm = 0.13, thigh = 0.19, shin = 0.19
}

extension FigurePose {
    private static func dir(_ deg: Double) -> CGPoint {
        let r = deg * .pi / 180
        return CGPoint(x: sin(r), y: -cos(r))
    }

    private static func add(_ p: CGPoint, _ v: CGPoint, _ s: Double) -> CGPoint {
        CGPoint(x: p.x + v.x * s, y: p.y + v.y * s)
    }

    var joints: FigureJoints {
        typealias L = FigureLengths
        let d = FigurePose.dir
        let a = FigurePose.add
        let hip = CGPoint.zero
        let sc = a(hip, d(torso), L.torso)
        let perp = d(torso + 90)
        let shoN = a(sc, perp, sw / 2), shoF = a(sc, perp, -sw / 2)
        let hipN = a(hip, perp, hw / 2), hipF = a(hip, perp, -hw / 2)
        let neck = a(sc, d(head), L.neck)
        let headC = a(neck, d(head), L.head)
        let elN = a(shoN, d(uaN), L.upperArm), hdN = a(elN, d(faN), L.forearm)
        let elF = a(shoF, d(uaF), L.upperArm), hdF = a(elF, d(faF), L.forearm)
        let knN = a(hipN, d(thN), L.thigh), ftN = a(knN, d(shN), L.shin)
        let knF = a(hipF, d(thF), L.thigh), ftF = a(knF, d(shF), L.shin)

        let anchorPoint: CGPoint
        switch anchor {
        case .hip: anchorPoint = hip
        case .footN: anchorPoint = ftN
        case .footF: anchorPoint = ftF
        case .handN: anchorPoint = hdN
        case .elbowN: anchorPoint = elN
        case .kneeN: anchorPoint = knN
        }
        let ox = ax - anchorPoint.x, oy = ay - anchorPoint.y
        func o(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + ox, y: p.y + oy) }
        return FigureJoints(hip: o(hip), shoulderC: o(sc), shoulderN: o(shoN), shoulderF: o(shoF),
                            hipN: o(hipN), hipF: o(hipF), neck: o(neck), head: o(headC),
                            elbowN: o(elN), handN: o(hdN), elbowF: o(elF), handF: o(hdF),
                            kneeN: o(knN), footN: o(ftN), kneeF: o(knF), footF: o(ftF))
    }
}

/// Simple scenery drawn behind the figure.
enum FigureProp {
    case rect(CGRect)
    case line(CGPoint, CGPoint)
}

/// A looping animation between keyframes.
struct FigureMotion {
    static let ground = 0.90

    var frames: [FigurePose]
    var cycle: Double = 2.4
    var props: [FigureProp] = []

    /// Pose at time `t` (seconds). Two frames ping-pong; more frames loop.
    func pose(at t: Double) -> FigurePose {
        guard frames.count > 1 else { return frames.first ?? FigurePose() }
        let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
        if frames.count == 2 {
            let x = 0.5 - 0.5 * cos(phase * 2 * .pi)
            return frames[0].lerp(to: frames[1], x)
        }
        let n = Double(frames.count)
        let pos = phase * n
        let i = Int(pos) % frames.count
        let j = (i + 1) % frames.count
        let local = pos - Double(Int(pos))
        let eased = local * local * (3 - 2 * local)
        return frames[i].lerp(to: frames[j], eased)
    }
}

// MARK: - Library of motions (designed & checked with a Python prototype)

extension FigureMotion {
    private static let G = FigureMotion.ground

    private static func P(torso: Double = 0, head: Double = 0,
                          uaN: Double = 180, faN: Double = 180, uaF: Double = 180, faF: Double = 180,
                          thN: Double = 180, shN: Double = 180, thF: Double = 180, shF: Double = 180,
                          front: Bool = false, anchor: FigurePose.Anchor = .footN,
                          ax: Double = 0.5, ay: Double = FigureMotion.ground) -> FigurePose {
        FigurePose(torso: torso, head: head, uaN: uaN, faN: faN, uaF: uaF, faF: faF,
                   thN: thN, shN: shN, thF: thF, shF: shF,
                   sw: front ? 0.13 : 0, hw: front ? 0.08 : 0, anchor: anchor, ax: ax, ay: ay)
    }

    private static let chair: [FigureProp] = [
        .rect(CGRect(x: 0.20, y: 0.71, width: 0.20, height: 0.03)),
        .line(CGPoint(x: 0.22, y: 0.74), CGPoint(x: 0.22, y: G)),
        .line(CGPoint(x: 0.38, y: 0.74), CGPoint(x: 0.38, y: G)),
        .line(CGPoint(x: 0.21, y: 0.71), CGPoint(x: 0.21, y: 0.46)),
    ]

    private static let stool: [FigureProp] = [
        .rect(CGRect(x: 0.22, y: 0.71, width: 0.22, height: 0.03)),
        .line(CGPoint(x: 0.24, y: 0.74), CGPoint(x: 0.24, y: G)),
        .line(CGPoint(x: 0.42, y: 0.74), CGPoint(x: 0.42, y: G)),
    ]

    static func motion(for kind: MotionKind) -> FigureMotion {
        switch kind {
        // Legs
        case .squat:
            return FigureMotion(frames: [P(uaN: 170, faN: 170, uaF: 172, faF: 172),
                                         P(torso: 38, head: 30, uaN: 95, faN: 92, uaF: 97, faF: 94, thN: 97, shN: 203, thF: 99, shF: 205)])
        case .sitToStand:
            return FigureMotion(frames: [P(uaN: 100, faN: 95, uaF: 102, faF: 97, ax: 0.56),
                                         P(torso: 22, head: 15, uaN: 95, faN: 92, uaF: 97, faF: 94, thN: 90, shN: 182, thF: 92, shF: 184, ax: 0.56)],
                                cycle: 2.6, props: chair)
        case .wallSit:
            return FigureMotion(frames: [P(uaN: 178, faN: 178, uaF: 176, faF: 176, thN: 90, shN: 180, thF: 92, shF: 180, ax: 0.56),
                                         P(head: 4, uaN: 176, faN: 176, uaF: 174, faF: 174, thN: 90, shN: 180, thF: 92, shF: 180, ax: 0.56)],
                                cycle: 3.5, props: [.line(CGPoint(x: 0.33, y: 0.12), CGPoint(x: 0.33, y: G))])
        case .lunge:
            return FigureMotion(frames: [P(uaN: 175, faN: 175, ax: 0.55),
                                         P(torso: 4, uaN: 178, faN: 178, uaF: 182, faF: 182, thN: 100, shN: 180, thF: 190, shF: 262, ax: 0.58)])
        case .splitSquat:
            return FigureMotion(frames: [P(torso: 4, thN: 145, shN: 180, thF: 205, shF: 300, ax: 0.60),
                                         P(torso: 8, thN: 100, shN: 180, thF: 188, shF: 290, ax: 0.60)],
                                props: [.rect(CGRect(x: 0.08, y: 0.80, width: 0.22, height: G - 0.80))])
        case .jumpSquat:
            return FigureMotion(frames: [P(torso: 38, head: 30, uaN: 205, faN: 200, uaF: 207, faF: 202, thN: 97, shN: 203, thF: 99, shF: 205),
                                         P(uaN: 10, faN: 5, uaF: 12, faF: 7, thN: 172, shN: 190, thF: 174, shF: 192, ay: G - 0.08),
                                         P(uaN: 175, faN: 175)], cycle: 1.8)
        case .calfRaise:
            return FigureMotion(frames: [P(uaN: 178, faN: 178), P(uaN: 178, faN: 178, ay: G - 0.05)], cycle: 2.0)
        case .highKnees:
            return FigureMotion(frames: [P(uaN: 150, faN: 70, uaF: 215, faF: 160, thN: 88, shN: 178, anchor: .footF, ay: G - 0.01),
                                         P(uaN: 215, faN: 160, uaF: 150, faF: 70, thF: 88, shF: 178, anchor: .footN, ay: G - 0.01)],
                                cycle: 0.8)
        case .jumpingJack:
            return FigureMotion(frames: [P(uaN: 172, faN: 174, uaF: 188, faF: 186, thN: 176, shN: 177, thF: 184, shF: 183, front: true, anchor: .hip, ay: 0.52),
                                         P(uaN: 35, faN: 20, uaF: 325, faF: 340, thN: 158, shN: 158, thF: 202, shF: 202, front: true, anchor: .hip, ay: 0.545)],
                                cycle: 1.1)
        case .sideLegLift:
            return FigureMotion(frames: [P(torso: 270, head: 275, uaN: 120, faN: 70, uaF: 270, faF: 270, thN: 90, shN: 90, thF: 92, shF: 92, anchor: .hip, ax: 0.50, ay: G - 0.04),
                                         P(torso: 270, head: 275, uaN: 120, faN: 70, uaF: 270, faF: 270, thN: 58, shN: 58, thF: 92, shF: 92, anchor: .hip, ax: 0.50, ay: G - 0.04)])
        // Hinge
        case .bridge:
            return FigureMotion(frames: [P(torso: 270, head: 272, uaN: 88, faN: 90, uaF: 90, faF: 92, thN: 55, shN: 160, thF: 57, shF: 162, anchor: .hip, ax: 0.45, ay: G - 0.035),
                                         P(torso: 250, head: 262, uaN: 88, faN: 90, uaF: 90, faF: 92, thN: 80, shN: 168, thF: 82, shF: 170, anchor: .footN, ax: 0.66)])
        case .singleBridge:
            return FigureMotion(frames: [P(torso: 270, head: 272, uaN: 88, faN: 90, uaF: 90, faF: 92, thN: 40, shN: 60, thF: 57, shF: 162, anchor: .hip, ax: 0.45, ay: G - 0.035),
                                         P(torso: 250, head: 262, uaN: 88, faN: 90, uaF: 90, faF: 92, thN: 70, shN: 72, thF: 82, shF: 170, anchor: .footF, ax: 0.66)])
        case .goodMorning:
            return FigureMotion(frames: [P(uaN: 40, faN: 150, uaF: 42, faF: 152),
                                         P(torso: 80, head: 75, uaN: 125, faN: 230, uaF: 127, faF: 232, thN: 192, shN: 178, thF: 194, shF: 178)],
                                cycle: 3.0)
        case .superman:
            return FigureMotion(frames: [P(torso: 90, head: 92, uaN: 90, faN: 90, uaF: 92, faF: 92, thN: 270, shN: 270, thF: 270, shF: 270, anchor: .hip, ax: 0.48, ay: G - 0.03),
                                         P(torso: 80, head: 78, uaN: 75, faN: 75, uaF: 77, faF: 77, thN: 262, shN: 262, thF: 262, shF: 262, anchor: .hip, ax: 0.48, ay: G - 0.03)],
                                cycle: 3.0)
        case .singleLegRDL:
            return FigureMotion(frames: [P(uaN: 178, faN: 178, thF: 182, shF: 178),
                                         P(torso: 85, head: 82, uaN: 180, faN: 180, uaF: 182, faF: 182, thN: 185, shN: 178, thF: 268, shF: 272)],
                                cycle: 3.0)
        case .skater:
            return FigureMotion(frames: [P(torso: 25, head: 20, uaN: 215, faN: 205, uaF: 130, faF: 120, thN: 165, shN: 185, thF: 230, shF: 245, ax: 0.62),
                                         P(torso: -25, head: -20, uaN: 230, faN: 240, uaF: 145, faF: 155, thN: 130, shN: 115, thF: 195, shF: 175, anchor: .footF, ax: 0.38)],
                                cycle: 1.4)
        // Push
        case .wallPush:
            return FigureMotion(frames: [P(torso: 12, head: 10, uaN: 95, faN: 92, uaF: 97, faF: 94, thN: 192, shN: 192, thF: 194, shF: 194, ax: 0.36),
                                         P(torso: 28, head: 26, uaN: 150, faN: 60, uaF: 152, faF: 62, thN: 208, shN: 208, thF: 210, shF: 210, ax: 0.36)],
                                props: [.line(CGPoint(x: 0.80, y: 0.08), CGPoint(x: 0.80, y: G))])
        case .inclinePush:
            return FigureMotion(frames: [P(torso: 55, head: 55, uaN: 165, faN: 165, uaF: 167, faF: 167, thN: 235, shN: 235, thF: 236, shF: 236, anchor: .handN, ax: 0.72, ay: 0.70),
                                         P(torso: 68, head: 66, uaN: 245, faN: 150, uaF: 247, faF: 152, thN: 248, shN: 248, thF: 249, shF: 249, anchor: .handN, ax: 0.72, ay: 0.70)],
                                props: [.rect(CGRect(x: 0.64, y: 0.70, width: 0.26, height: G - 0.70))])
        case .kneePush:
            return FigureMotion(frames: [P(torso: 60, head: 62, thN: 240, shN: 275, thF: 242, shF: 277, anchor: .handN, ax: 0.70),
                                         P(torso: 80, head: 80, uaN: 290, faN: 165, uaF: 292, faF: 167, thN: 258, shN: 285, thF: 260, shF: 287, anchor: .handN, ax: 0.70)])
        case .pushUp:
            return FigureMotion(frames: [P(torso: 65, head: 66, thN: 245, shN: 245, thF: 246, shF: 246, anchor: .handN, ax: 0.72),
                                         P(torso: 82, head: 80, uaN: 290, faN: 165, uaF: 292, faF: 167, thN: 262, shN: 262, thF: 263, shF: 263, anchor: .handN, ax: 0.72)])
        case .declinePush:
            return FigureMotion(frames: [P(torso: 93, head: 96, thN: 273, shN: 273, thF: 274, shF: 274, anchor: .footN, ax: 0.12, ay: 0.60),
                                         P(torso: 106, head: 100, uaN: 290, faN: 165, uaF: 292, faF: 167, thN: 286, shN: 286, thF: 287, shF: 287, anchor: .footN, ax: 0.12, ay: 0.60)],
                                props: [.rect(CGRect(x: 0.02, y: 0.60, width: 0.22, height: G - 0.60))])
        case .pikePush:
            return FigureMotion(frames: [P(torso: 150, head: 160, uaN: 150, faN: 150, uaF: 152, faF: 152, thN: 210, shN: 210, thF: 212, shF: 212, anchor: .handN, ax: 0.66),
                                         P(torso: 125, head: 145, uaN: 230, faN: 140, uaF: 232, faF: 142, thN: 212, shN: 212, thF: 214, shF: 214, anchor: .handN, ax: 0.66)])
        // Core
        case .plank:
            return FigureMotion(frames: [P(torso: 80, head: 82, faN: 90, faF: 90, thN: 260, shN: 260, thF: 261, shF: 261, anchor: .elbowN, ax: 0.66, ay: G - 0.01),
                                         P(torso: 78, head: 80, faN: 90, faF: 90, thN: 258, shN: 258, thF: 259, shF: 259, anchor: .elbowN, ax: 0.66, ay: G - 0.01)],
                                cycle: 3.5)
        case .sidePlank:
            return FigureMotion(frames: [P(torso: 75, head: 75, faN: 90, uaF: 345, faF: 345, thN: 255, shN: 255, thF: 255, shF: 255, front: true, anchor: .elbowN, ax: 0.70, ay: G - 0.01),
                                         P(torso: 68, head: 70, faN: 90, uaF: 345, faF: 345, thN: 248, shN: 248, thF: 248, shF: 248, front: true, anchor: .elbowN, ax: 0.70, ay: G - 0.01)],
                                cycle: 3.0)
        case .shoulderTaps:
            return FigureMotion(frames: [P(torso: 65, head: 66, thN: 245, shN: 245, thF: 246, shF: 246, anchor: .handN, ax: 0.72),
                                         P(torso: 65, head: 66, uaF: 160, faF: 330, thN: 245, shN: 245, thF: 246, shF: 246, anchor: .handN, ax: 0.72)],
                                cycle: 1.6)
        case .mountainClimber:
            return FigureMotion(frames: [P(torso: 65, head: 66, thN: 140, shN: 250, thF: 246, shF: 246, anchor: .handN, ax: 0.72),
                                         P(torso: 65, head: 66, thN: 246, shN: 246, thF: 140, shF: 250, anchor: .handN, ax: 0.72)],
                                cycle: 0.8)
        case .deadBug:
            return FigureMotion(frames: [P(torso: 270, head: 270, uaN: 0, faN: 0, uaF: 0, faF: 0, thN: 0, shN: 90, thF: 2, shF: 92, anchor: .hip, ax: 0.55, ay: G - 0.03),
                                         P(torso: 270, head: 270, uaN: 0, faN: 0, uaF: 300, faF: 290, thN: 55, shN: 80, thF: 2, shF: 92, anchor: .hip, ax: 0.55, ay: G - 0.03)],
                                cycle: 3.0)
        case .birdDog:
            return FigureMotion(frames: [P(torso: 90, head: 95, thN: 180, shN: 270, thF: 180, shF: 270, anchor: .hip, ax: 0.38, ay: G - 0.19),
                                         P(torso: 90, head: 92, uaF: 90, faF: 90, thN: 270, shN: 270, thF: 180, shF: 270, anchor: .hip, ax: 0.38, ay: G - 0.19)],
                                cycle: 3.0)
        case .bicycle:
            return FigureMotion(frames: [P(torso: 300, head: 320, uaN: 330, faN: 150, uaF: 330, faF: 150, thN: 40, shN: 110, thF: 80, shF: 80, anchor: .hip, ax: 0.52, ay: G - 0.03),
                                         P(torso: 300, head: 320, uaN: 330, faN: 150, uaF: 330, faF: 150, thN: 80, shN: 80, thF: 40, shF: 110, anchor: .hip, ax: 0.52, ay: G - 0.03)],
                                cycle: 1.6)
        case .crunch:
            return FigureMotion(frames: [P(torso: 270, head: 272, uaN: 90, faN: 90, uaF: 90, faF: 90, thN: 50, shN: 150, thF: 52, shF: 152, anchor: .footN, ax: 0.72),
                                         P(torso: 305, head: 320, uaN: 80, faN: 80, uaF: 82, faF: 82, thN: 50, shN: 150, thF: 52, shF: 152, anchor: .footN, ax: 0.72)],
                                cycle: 1.8)
        case .hollowHold:
            return FigureMotion(frames: [P(torso: 285, head: 300, uaN: 280, faN: 280, uaF: 282, faF: 282, thN: 75, shN: 75, thF: 76, shF: 76, anchor: .hip, ax: 0.52, ay: G - 0.03),
                                         P(torso: 282, head: 298, uaN: 278, faN: 278, uaF: 280, faF: 280, thN: 72, shN: 72, thF: 73, shF: 73, anchor: .hip, ax: 0.52, ay: G - 0.03)],
                                cycle: 3.0)
        // Mobility
        case .armCircles:
            return FigureMotion(frames: [P(uaN: 90, faN: 90, uaF: 270, faF: 270, front: true),
                                         P(uaN: 70, faN: 70, uaF: 290, faF: 290, front: true),
                                         P(uaN: 90, faN: 90, uaF: 270, faF: 270, front: true),
                                         P(uaN: 110, faN: 110, uaF: 250, faF: 250, front: true)], cycle: 1.6)
        case .wallAngel:
            return FigureMotion(frames: [P(uaN: 100, faN: 10, uaF: 260, faF: 350, thN: 178, shN: 178, thF: 182, shF: 182, front: true),
                                         P(uaN: 30, faN: 10, uaF: 330, faF: 350, thN: 178, shN: 178, thF: 182, shF: 182, front: true)],
                                cycle: 3.0)
        case .hipCircles:
            return FigureMotion(frames: [P(uaN: 150, faN: 240, uaF: 210, faF: 120, thN: 176, shN: 178, thF: 184, shF: 182, front: true, ax: 0.55),
                                         P(torso: 8, uaN: 150, faN: 240, uaF: 210, faF: 120, thN: 168, shN: 176, thF: 178, shF: 186, front: true, ax: 0.55),
                                         P(uaN: 150, faN: 240, uaF: 210, faF: 120, thN: 176, shN: 178, thF: 184, shF: 182, front: true, ax: 0.55),
                                         P(torso: -8, uaN: 150, faN: 240, uaF: 210, faF: 120, thN: 184, shN: 184, thF: 192, shF: 188, front: true, ax: 0.55)],
                                cycle: 3.2)
        case .catCow:
            return FigureMotion(frames: [P(torso: 80, head: 110, uaN: 190, faN: 190, uaF: 190, faF: 190, thN: 180, shN: 270, thF: 180, shF: 270, anchor: .hip, ax: 0.38, ay: G - 0.19),
                                         P(torso: 100, head: 70, uaN: 170, faN: 170, uaF: 170, faF: 170, thN: 180, shN: 270, thF: 180, shF: 270, anchor: .hip, ax: 0.38, ay: G - 0.19)],
                                cycle: 4.0)
        case .inchworm:
            return FigureMotion(frames: [P(uaN: 178, faN: 178),
                                         P(torso: 130, head: 150, uaN: 170, faN: 170, uaF: 172, faF: 172, thN: 185, shN: 185, thF: 186, shF: 186),
                                         P(torso: 65, head: 66, thN: 245, shN: 245, thF: 246, shF: 246, anchor: .footN, ax: 0.18)],
                                cycle: 4.5)
        case .lungeReach:
            return FigureMotion(frames: [P(torso: 60, head: 65, thN: 100, shN: 180, thF: 230, shF: 275, ax: 0.62),
                                         P(torso: 30, head: 10, uaF: 0, faF: 0, thN: 100, shN: 180, thF: 230, shF: 275, ax: 0.62)],
                                cycle: 3.2)
        case .legSwing:
            return FigureMotion(frames: [P(uaN: 120, faN: 110, uaF: 170, faF: 170, thN: 130, shN: 140, anchor: .footF),
                                         P(uaN: 200, faN: 200, uaF: 150, faF: 140, thN: 215, shN: 225, anchor: .footF)],
                                cycle: 1.6)
        // Recovery
        case .neckTilt:
            return FigureMotion(frames: [P(head: -25, front: true), P(head: 25, front: true)], cycle: 5.0)
        case .shoulderRoll:
            return FigureMotion(frames: [P(front: true), P(uaN: 165, faN: 175, uaF: 195, faF: 185, front: true)], cycle: 2.5)
        case .crossBody:
            return FigureMotion(frames: [P(uaN: 270, faN: 270, uaF: 210, faF: 60, front: true),
                                         P(uaN: 280, faN: 280, uaF: 215, faF: 70, front: true)], cycle: 4.0)
        case .wristCircles:
            return FigureMotion(frames: [P(uaN: 160, faN: 60, uaF: 200, faF: 300, front: true),
                                         P(uaN: 160, faN: 80, uaF: 200, faF: 280, front: true)], cycle: 1.4)
        case .childPose:
            return FigureMotion(frames: [P(torso: 95, head: 105, uaN: 100, faN: 95, uaF: 102, faF: 97, thN: 123, shN: 270, thF: 125, shF: 272, anchor: .kneeN, ax: 0.45, ay: G - 0.01),
                                         P(torso: 91, head: 101, uaN: 98, faN: 93, uaF: 100, faF: 95, thN: 123, shN: 270, thF: 125, shF: 272, anchor: .kneeN, ax: 0.45, ay: G - 0.01)],
                                cycle: 5.0)
        case .figure4:
            return FigureMotion(frames: [P(torso: 270, head: 272, uaN: 45, faN: 70, uaF: 47, faF: 72, thN: 25, shN: 95, thF: 40, shF: 150, anchor: .hip, ax: 0.45, ay: G - 0.03),
                                         P(torso: 270, head: 272, uaN: 35, faN: 60, uaF: 37, faF: 62, thN: 15, shN: 85, thF: 28, shF: 135, anchor: .hip, ax: 0.45, ay: G - 0.03)],
                                cycle: 5.0)
        case .kneeMassage:
            return FigureMotion(frames: [P(torso: 5, head: 10, uaN: 150, faN: 110, uaF: 152, faF: 112, thN: 90, shN: 180, thF: 92, shF: 182, ax: 0.62),
                                         P(torso: 8, head: 12, uaN: 165, faN: 95, uaF: 167, faF: 97, thN: 90, shN: 180, thF: 92, shF: 182, ax: 0.62)],
                                cycle: 2.0, props: stool)
        case .seatedAnkle:
            return FigureMotion(frames: [P(torso: 5, head: 10, uaN: 160, faN: 170, uaF: 165, faF: 175, thN: 90, shN: 150, thF: 92, shF: 182, anchor: .footF, ax: 0.60),
                                         P(torso: 5, head: 10, uaN: 160, faN: 170, uaF: 165, faF: 175, thN: 90, shN: 130, thF: 92, shF: 182, anchor: .footF, ax: 0.60)],
                                cycle: 1.6, props: stool)
        }
    }
}
