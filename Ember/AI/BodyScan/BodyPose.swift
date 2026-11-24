import CoreGraphics
import Foundation
import Vision

/// Joints Ember uses from Apple Vision's body-pose model.
enum Joint: String, CaseIterable, Hashable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: return .nose
        case .leftEye: return .leftEye
        case .rightEye: return .rightEye
        case .leftEar: return .leftEar
        case .rightEar: return .rightEar
        case .neck: return .neck
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .root: return .root
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        }
    }

    /// Bones drawn in the live overlay.
    static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose),
    ]
}

/// One detected pose. Points are normalised to the image (0...1, origin top-left).
struct BodyPose {
    var points: [Joint: CGPoint]
    /// Image width / height, so geometry can be done in square units.
    var aspect: CGFloat

    init(points: [Joint: CGPoint], aspect: CGFloat) {
        self.points = points
        self.aspect = aspect
    }

    init?(observation: VNHumanBodyPoseObservation, aspect: CGFloat, minConfidence: Float = 0.3) {
        guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
        var pts: [Joint: CGPoint] = [:]
        for joint in Joint.allCases {
            if let p = recognized[joint.visionName], p.confidence >= minConfidence {
                pts[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
            }
        }
        guard pts.count >= 6 else { return nil }
        self.points = pts
        self.aspect = aspect
    }

    /// Point in "height units" (x scaled by aspect) for angle / distance maths.
    func g(_ j: Joint) -> CGPoint? {
        guard let p = points[j] else { return nil }
        return CGPoint(x: p.x * aspect, y: p.y)
    }

    func has(_ joints: [Joint]) -> Bool { joints.allSatisfy { points[$0] != nil } }

    /// Whole body visible and inside the frame.
    var isFullBodyVisible: Bool {
        guard has([.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]),
              let nose = points[.nose], let la = points[.leftAnkle], let ra = points[.rightAnkle] else { return false }
        return nose.y > 0.02 && la.y < 0.99 && ra.y < 0.99
    }

    var armsOverhead: Bool {
        guard let lw = points[.leftWrist], let rw = points[.rightWrist], let nose = points[.nose] else { return false }
        return lw.y < nose.y && rw.y < nose.y
    }

    // MARK: Geometry

    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Tilt of the line a→b from horizontal, in degrees (0 = level).
    static func tilt(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = abs(Double(b.x - a.x)), dy = abs(Double(b.y - a.y))
        guard dx > 0.0001 else { return 90 }
        return atan2(dy, dx) * 180 / .pi
    }

    /// Angle between vectors u and v in degrees (0...180).
    static func angle(_ u: CGPoint, _ v: CGPoint) -> Double {
        let dot = Double(u.x * v.x + u.y * v.y)
        let mag = Double(hypot(u.x, u.y) * hypot(v.x, v.y))
        guard mag > 0.000001 else { return 0 }
        return acos(max(-1, min(1, dot / mag))) * 180 / .pi
    }

    /// Shoulder flexion-ish: angle between torso (hip→shoulder) and arm (shoulder→wrist). 180 = arm straight overhead.
    func reachAngle(left: Bool) -> Double? {
        guard let s = g(left ? .leftShoulder : .rightShoulder),
              let h = g(left ? .leftHip : .rightHip),
              let w = g(left ? .leftWrist : .rightWrist) else { return nil }
        let torso = CGPoint(x: s.x - h.x, y: s.y - h.y)
        let arm = CGPoint(x: w.x - s.x, y: w.y - s.y)
        // Arm hanging down → 0°, arm straight overhead (parallel to torso) → 180°.
        return 180 - BodyPose.angle(torso, arm)
    }
}

/// A small sample pose for previews / the simulator demo.
extension BodyPose {
    static let sampleStanding = BodyPose(points: [
        .nose: CGPoint(x: 0.50, y: 0.16), .neck: CGPoint(x: 0.50, y: 0.24),
        .leftShoulder: CGPoint(x: 0.40, y: 0.26), .rightShoulder: CGPoint(x: 0.60, y: 0.27),
        .leftElbow: CGPoint(x: 0.37, y: 0.38), .rightElbow: CGPoint(x: 0.63, y: 0.38),
        .leftWrist: CGPoint(x: 0.36, y: 0.49), .rightWrist: CGPoint(x: 0.64, y: 0.49),
        .leftHip: CGPoint(x: 0.44, y: 0.52), .rightHip: CGPoint(x: 0.56, y: 0.52),
        .leftKnee: CGPoint(x: 0.44, y: 0.70), .rightKnee: CGPoint(x: 0.56, y: 0.70),
        .leftAnkle: CGPoint(x: 0.44, y: 0.88), .rightAnkle: CGPoint(x: 0.56, y: 0.88),
    ], aspect: 0.5625)
}
