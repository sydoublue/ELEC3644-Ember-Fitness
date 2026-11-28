import Foundation

/// A 2D body landmark. Coordinates are normalized, origin at the bottom left.
nonisolated struct PosePoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var confidence: Double
}

nonisolated enum PoseJoint: String, CaseIterable, Hashable, Sendable {
    case nose
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

nonisolated struct FormFeedback: Equatable, Sendable {
    var title: String
    var detail: String
    var tone: Tone

    nonisolated enum Tone: Equatable, Sendable {
        case searching, good, adjust, guide
    }

    static let noPerson = FormFeedback(
        title: "No person in frame yet.",
        detail: "Step back so your whole body is visible.",
        tone: .searching
    )

    static let incomplete = FormFeedback(
        title: "Move so the whole body is in frame.",
        detail: "Form check needs the hips, knees, and shoulders.",
        tone: .searching
    )

    static let guideOnly = FormFeedback(
        title: "A guide only. Follow the cue.",
        detail: "This move has no angle rule yet.",
        tone: .guide
    )
}

nonisolated struct PoseSnapshot: Equatable, Sendable {
    var joints: [PoseJoint: PosePoint]
    var feedback: FormFeedback
}

/// Rule-based joint angles on landmarks from the system pose request.
/// The model only supplies points. These checks do not leave the phone.
nonisolated enum FormEvaluator {
    static let minimumConfidence = 0.35

    static func evaluate(exerciseId: String, joints: [PoseJoint: PosePoint]) -> FormFeedback {
        let visible = joints.values.filter { $0.confidence >= minimumConfidence }.count
        guard visible >= 4 else { return .noPerson }
        switch family(for: exerciseId) {
        case .squat:
            return squat(joints)
        case .push:
            return push(exerciseId: exerciseId, joints: joints)
        case .plank:
            return plank(joints)
        case .climber:
            return climber(joints)
        case .bridge:
            return bridge(joints)
        case .hinge:
            return hinge(joints)
        case .lunge:
            return lunge(joints)
        case .guide:
            return .guideOnly
        }
    }

    static func reference(for exerciseId: String) -> String {
        switch family(for: exerciseId) {
        case .squat:
            "Reference: sit the hips back, knees over the toes."
        case .push:
            "Reference: straight body, chest toward the floor."
        case .plank, .climber:
            "Reference: a straight line from head to heels."
        case .bridge:
            "Reference: press the hips up until they open."
        case .hinge:
            "Reference: hips back, knees only softly bent."
        case .lunge:
            "Reference: step back and lower the back knee."
        case .guide:
            "Reference: follow the cue. This check draws your outline."
        }
    }

    private enum Family {
        case squat, push, plank, climber, bridge, hinge, lunge, guide
    }

    private static func family(for exerciseId: String) -> Family {
        switch exerciseId {
        case "squat", "bodyweight-squat", "sit-to-stand", "jump-squat", "wall-sit":
            .squat
        case "push-up", "knee-push-up", "wall-push-up", "incline-push-up", "pike-push-up", "decline-push-up":
            .push
        case "plank", "forearm-plank", "side-plank", "hollow-hold", "shoulder-taps":
            .plank
        case "mountain-climber", "mountain-climbers":
            .climber
        case "glute-bridge", "single-leg-bridge":
            .bridge
        case "hip-hinge", "single-leg-hinge", "good-morning":
            .hinge
        case "reverse-lunge", "split-squat":
            .lunge
        default:
            .guide
        }
    }

    private enum Side {
        case left, right
    }

    private enum Part {
        case shoulder, elbow, wrist, hip, knee, ankle
    }

    private static func point(_ joints: [PoseJoint: PosePoint], _ side: Side, _ part: Part) -> PosePoint? {
        let name: PoseJoint
        switch (side, part) {
        case (.left, .shoulder): name = .leftShoulder
        case (.right, .shoulder): name = .rightShoulder
        case (.left, .elbow): name = .leftElbow
        case (.right, .elbow): name = .rightElbow
        case (.left, .wrist): name = .leftWrist
        case (.right, .wrist): name = .rightWrist
        case (.left, .hip): name = .leftHip
        case (.right, .hip): name = .rightHip
        case (.left, .knee): name = .leftKnee
        case (.right, .knee): name = .rightKnee
        case (.left, .ankle): name = .leftAnkle
        case (.right, .ankle): name = .rightAnkle
        }
        guard let found = joints[name], found.confidence >= minimumConfidence else { return nil }
        return found
    }

    private static func bestSide(_ joints: [PoseJoint: PosePoint], parts: [Part]) -> Side? {
        func score(_ side: Side) -> Double? {
            var total = 0.0
            for part in parts {
                guard let found = point(joints, side, part) else { return nil }
                total += found.confidence
            }
            return total
        }
        let left = score(.left)
        let right = score(.right)
        switch (left, right) {
        case let (lhs?, rhs?):
            return lhs >= rhs ? .left : .right
        case (_?, nil):
            return .left
        case (nil, _?):
            return .right
        default:
            return nil
        }
    }

    private static func angle(_ a: PosePoint, _ b: PosePoint, _ c: PosePoint) -> Double? {
        let abx = a.x - b.x
        let aby = a.y - b.y
        let cbx = c.x - b.x
        let cby = c.y - b.y
        let dot = abx * cbx + aby * cby
        let magnitude = (abx * abx + aby * aby).squareRoot() * (cbx * cbx + cby * cby).squareRoot()
        guard magnitude > 1e-6 else { return nil }
        let cosine = min(1, max(-1, dot / magnitude))
        return acos(cosine) * 180 / .pi
    }

    private static func detail(_ label: String, _ degrees: Double, _ target: String) -> String {
        "\(label) \(Int(degrees.rounded()))° · \(target)"
    }

    private static func squat(_ joints: [PoseJoint: PosePoint]) -> FormFeedback {
        let parts: [Part] = [.hip, .knee, .ankle]
        guard let side = bestSide(joints, parts: parts),
              let hip = point(joints, side, .hip),
              let knee = point(joints, side, .knee),
              let ankle = point(joints, side, .ankle),
              let kneeAngle = angle(hip, knee, ankle) else {
            return .incomplete
        }
        if kneesCaving(joints) {
            return FormFeedback(
                title: "Push the knees out over the toes.",
                detail: detail("Knee", kneeAngle, "knees over the toes"),
                tone: .adjust
            )
        }
        if kneeAngle <= 115 {
            return FormFeedback(
                title: "Depth looks right.",
                detail: detail("Knee", kneeAngle, "bottom is under 115°"),
                tone: .good
            )
        }
        if kneeAngle >= 155 {
            return FormFeedback(
                title: "Standing tall.",
                detail: detail("Knee", kneeAngle, "top is a straight leg"),
                tone: .good
            )
        }
        return FormFeedback(
            title: "Sit the hips back as you lower.",
            detail: detail("Knee", kneeAngle, "keep sitting the hips back"),
            tone: .guide
        )
    }

    private static func kneesCaving(_ joints: [PoseJoint: PosePoint]) -> Bool {
        guard let leftHip = point(joints, .left, .hip),
              let rightHip = point(joints, .right, .hip),
              let leftKnee = point(joints, .left, .knee),
              let rightKnee = point(joints, .right, .knee),
              let leftAnkle = point(joints, .left, .ankle),
              let rightAnkle = point(joints, .right, .ankle),
              let leftBend = angle(leftHip, leftKnee, leftAnkle),
              let rightBend = angle(rightHip, rightKnee, rightAnkle) else {
            return false
        }
        let midline = (leftHip.x + rightHip.x) / 2
        func caved(_ knee: PosePoint, _ ankle: PosePoint, bend: Double) -> Bool {
            guard bend < 150 else { return false }
            let ankleDistance = abs(ankle.x - midline)
            let kneeDistance = abs(knee.x - midline)
            return ankleDistance > 0.05 && kneeDistance + 0.035 < ankleDistance
        }
        return caved(leftKnee, leftAnkle, bend: leftBend)
            || caved(rightKnee, rightAnkle, bend: rightBend)
    }

    private static func push(exerciseId: String, joints: [PoseJoint: PosePoint]) -> FormFeedback {
        let usesKnee = exerciseId == "knee-push-up"
        let lineParts: [Part] = usesKnee
            ? [.shoulder, .hip, .knee, .elbow, .wrist]
            : [.shoulder, .hip, .ankle, .elbow, .wrist]
        guard let side = bestSide(joints, parts: lineParts),
              let shoulder = point(joints, side, .shoulder),
              let hip = point(joints, side, .hip),
              let elbow = point(joints, side, .elbow),
              let wrist = point(joints, side, .wrist),
              let lineEnd = point(joints, side, usesKnee ? .knee : .ankle),
              let body = angle(shoulder, hip, lineEnd),
              let elbowAngle = angle(shoulder, elbow, wrist) else {
            return .incomplete
        }
        if body < 150 {
            return FormFeedback(
                title: "Keep a straight line from head to heels.",
                detail: detail("Body", body, "head, hips, and heels in one line"),
                tone: .adjust
            )
        }
        if elbowAngle <= 100 {
            return FormFeedback(
                title: "Chest and body line look right.",
                detail: detail("Elbow", elbowAngle, "chest toward the floor"),
                tone: .good
            )
        }
        if elbowAngle >= 155 {
            return FormFeedback(
                title: "Arms are straight.",
                detail: detail("Elbow", elbowAngle, "arms straight at the top"),
                tone: .good
            )
        }
        return FormFeedback(
            title: "Lower the chest, keep the body long.",
            detail: detail("Elbow", elbowAngle, "chest toward the floor"),
            tone: .guide
        )
    }

    private static func plank(_ joints: [PoseJoint: PosePoint]) -> FormFeedback {
        guard let side = bestSide(joints, parts: [.shoulder, .hip, .ankle]),
              let shoulder = point(joints, side, .shoulder),
              let hip = point(joints, side, .hip),
              let ankle = point(joints, side, .ankle),
              let body = angle(shoulder, hip, ankle) else {
            return .incomplete
        }
        if body >= 160 {
            return FormFeedback(
                title: "Body line looks straight.",
                detail: detail("Body", body, "head to heels"),
                tone: .good
            )
        }
        return FormFeedback(
            title: "Lengthen into a straight line.",
            detail: detail("Body", body, "head to heels"),
            tone: .adjust
        )
    }

    private static func climber(_ joints: [PoseJoint: PosePoint]) -> FormFeedback {
        let line = plank(joints)
        guard line.tone == .good else { return line }
        return FormFeedback(
            title: "Drive one knee in, then the other.",
            detail: line.detail,
            tone: .guide
        )
    }

    private static func bridge(_ joints: [PoseJoint: PosePoint]) -> FormFeedback {
        guard let side = bestSide(joints, parts: [.shoulder, .hip, .knee]),
              let shoulder = point(joints, side, .shoulder),
              let hip = point(joints, side, .hip),
              let knee = point(joints, side, .knee),
              let hipAngle = angle(shoulder, hip, knee) else {
            return .incomplete
        }
        if hipAngle >= 150 {
            return FormFeedback(
                title: "Hips are up.",
                detail: detail("Hip", hipAngle, "hips open at the top"),
                tone: .good
            )
        }
        if hipAngle <= 120 {
            return FormFeedback(
                title: "Press the hips a little higher.",
                detail: detail("Hip", hipAngle, "press the hips up"),
                tone: .adjust
            )
        }
        return FormFeedback(
            title: "Keep pressing the hips up.",
            detail: detail("Hip", hipAngle, "keep pressing the hips up"),
            tone: .guide
        )
    }

    private static func hinge(_ joints: [PoseJoint: PosePoint]) -> FormFeedback {
        guard let side = bestSide(joints, parts: [.shoulder, .hip, .knee, .ankle]),
              let shoulder = point(joints, side, .shoulder),
              let hip = point(joints, side, .hip),
              let knee = point(joints, side, .knee),
              let ankle = point(joints, side, .ankle),
              let hipAngle = angle(shoulder, hip, knee),
              let kneeAngle = angle(hip, knee, ankle) else {
            return .incomplete
        }
        if kneeAngle < 130 {
            return FormFeedback(
                title: "Soften the knees only. Hinge at the hips.",
                detail: detail("Knee", kneeAngle, "knees soft, not a squat"),
                tone: .adjust
            )
        }
        if hipAngle <= 125 {
            return FormFeedback(
                title: "Hinge looks right.",
                detail: detail("Hip", hipAngle, "hips back, chest long"),
                tone: .good
            )
        }
        if hipAngle >= 160 {
            return FormFeedback(
                title: "Push the hips back.",
                detail: detail("Hip", hipAngle, "push the hips back"),
                tone: .guide
            )
        }
        return FormFeedback(
            title: "Keep hinging from the hips.",
            detail: detail("Hip", hipAngle, "keep hinging from the hips"),
            tone: .guide
        )
    }

    private static func lunge(_ joints: [PoseJoint: PosePoint]) -> FormFeedback {
        var bends: [Double] = []
        for side in [Side.left, Side.right] {
            guard let hip = point(joints, side, .hip),
                  let knee = point(joints, side, .knee),
                  let ankle = point(joints, side, .ankle),
                  let bend = angle(hip, knee, ankle) else { continue }
            bends.append(bend)
        }
        guard let lead = bends.min() else { return .incomplete }
        if lead < 65 {
            return FormFeedback(
                title: "Don't drop the back knee into the floor.",
                detail: detail("Knee", lead, "stop above the floor"),
                tone: .adjust
            )
        }
        if lead <= 115 {
            return FormFeedback(
                title: "Depth looks right.",
                detail: detail("Knee", lead, "front thigh about level"),
                tone: .good
            )
        }
        if bends.allSatisfy({ $0 >= 155 }) {
            return FormFeedback(
                title: "Step back and lower the back knee.",
                detail: detail("Knee", lead, "step back and lower"),
                tone: .guide
            )
        }
        return FormFeedback(
            title: "Lower until the front thigh is about level.",
            detail: detail("Knee", lead, "front thigh about level"),
            tone: .guide
        )
    }
}
