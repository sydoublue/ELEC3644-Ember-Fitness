import Foundation

/// A bodyweight exercise in Ember's library.
struct Exercise: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: MovementCategory
    /// 1 (easiest) ... 5 (hardest)
    let level: Int
    /// One-line instruction shown during the session.
    let instruction: String
    /// Step-by-step how-to shown on the detail screen.
    let steps: [String]
    /// Short form cues.
    let cues: [String]
    let muscles: [String]
    /// Body areas this move puts pressure on. Excluded when the user reports discomfort there.
    let stresses: Set<BodyArea>
    let isJumping: Bool
    /// Recovery (self-massage / stretch) item. Never chosen as a regular slot.
    let isRecovery: Bool
    /// For recovery items: which area it eases.
    let eases: BodyArea?
    /// "Switch sides halfway" hint.
    let perSide: Bool
    let motion: MotionKind
    /// Optional curated YouTube video id. When nil, the app searches YouTube with `videoQuery`.
    let youtubeID: String?

    init(id: String, name: String, category: MovementCategory, level: Int,
         instruction: String, steps: [String], cues: [String], muscles: [String],
         stresses: Set<BodyArea> = [], isJumping: Bool = false, isRecovery: Bool = false,
         eases: BodyArea? = nil, perSide: Bool = false, motion: MotionKind, youtubeID: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.level = level
        self.instruction = instruction
        self.steps = steps
        self.cues = cues
        self.muscles = muscles
        self.stresses = stresses
        self.isJumping = isJumping
        self.isRecovery = isRecovery
        self.eases = eases
        self.perSide = perSide
        self.motion = motion
        self.youtubeID = youtubeID
    }

    /// Query used to find demo videos.
    var videoQuery: String { "how to do \(name.lowercased()) proper form" }
}

/// Animated figure motions (see `FigureMotions`).
enum MotionKind: String, Codable, Hashable, CaseIterable {
    case squat, sitToStand, wallSit, lunge, splitSquat, jumpSquat, calfRaise, highKnees, jumpingJack, sideLegLift
    case bridge, singleBridge, goodMorning, superman, singleLegRDL, skater
    case wallPush, inclinePush, kneePush, pushUp, declinePush, pikePush
    case plank, sidePlank, shoulderTaps, mountainClimber, deadBug, birdDog, bicycle, crunch, hollowHold
    case armCircles, wallAngel, hipCircles, catCow, inchworm, lungeReach, legSwing
    case neckTilt, shoulderRoll, crossBody, wristCircles, childPose, figure4, kneeMassage, seatedAnkle
}
