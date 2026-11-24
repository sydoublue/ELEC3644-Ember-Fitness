import Foundation
import CoreGraphics

// MARK: - Results model

/// Raw measurements from a scan. Nil = couldn't measure.
struct ScanMetrics: Codable, Hashable {
    var shoulderTilt: Double?
    var hipTilt: Double?
    var headTilt: Double?
    var reachLeft: Double?
    var reachRight: Double?
    /// Hip drop as a fraction of standing leg length (0.5 ≈ thighs parallel).
    var squatDepth: Double?
    /// Knee gap / ankle gap at the bottom of the squat (< 0.85 ≈ knees caving in).
    var kneeTracking: Double?
    /// Sideways hip shift at the bottom, as a fraction of stance width.
    var lateralShift: Double?
    var squatReps: Int = 0
}

enum ScanFinding: String, Codable, CaseIterable, Hashable, Identifiable {
    case unevenShoulders, unevenHips, headTilt, limitedOverhead, unevenReach
    case shallowSquat, kneesCaving, lateralShift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unevenShoulders: return "Uneven shoulders"
        case .unevenHips: return "Uneven hips"
        case .headTilt: return "Head tilts to one side"
        case .limitedOverhead: return "Limited overhead reach"
        case .unevenReach: return "One arm reaches higher"
        case .shallowSquat: return "Shallow squat"
        case .kneesCaving: return "Knees drift inward"
        case .lateralShift: return "Shifting to one side"
        }
    }

    var symbol: String {
        switch self {
        case .unevenShoulders, .unevenReach, .limitedOverhead: return "figure.arms.open"
        case .unevenHips, .lateralShift: return "figure.stand"
        case .headTilt: return "person.crop.circle"
        case .shallowSquat, .kneesCaving: return "figure.cross.training"
        }
    }

    var why: String {
        switch self {
        case .unevenShoulders: return "Often from one-sided habits like carrying a bag or phone. Upper-back mobility and side-core work help."
        case .unevenHips: return "One side may be working harder. Single-leg glute work and side-lying lifts build balance."
        case .headTilt: return "Common with long screen time. Gentle neck ease and wall angels encourage a centred posture."
        case .limitedOverhead: return "Tight chest or upper back can limit reach. Wall angels and arm circles open things up."
        case .unevenReach: return "One shoulder moves more freely. Slow mobility work on both sides evens it out."
        case .shallowSquat: return "Hip and ankle mobility plus assisted squats help you sit deeper with control."
        case .kneesCaving: return "Usually means the glutes aren't holding the knees out. Bridges and side-lying lifts strengthen them."
        case .lateralShift: return "You may favour one leg. Single-leg moves train both sides evenly."
        }
    }

    var focus: [MovementCategory] {
        switch self {
        case .unevenShoulders: return [.mobility, .core]
        case .unevenHips, .kneesCaving: return [.hinge]
        case .headTilt, .limitedOverhead, .unevenReach: return [.mobility]
        case .shallowSquat: return [.squat, .mobility]
        case .lateralShift: return [.hinge, .squat]
        }
    }

    var exercises: [String] {
        switch self {
        case .unevenShoulders: return ["wall-angels", "side-plank", "arm-circles", "shoulder-ease"]
        case .unevenHips: return ["single-leg-bridge", "side-leg-lift", "hip-circles", "side-plank"]
        case .headTilt: return ["wall-angels", "neck-ease"]
        case .limitedOverhead: return ["wall-angels", "arm-circles", "inchworm", "cat-cow"]
        case .unevenReach: return ["wall-angels", "arm-circles"]
        case .shallowSquat: return ["sit-to-stand", "bodyweight-squat", "hip-circles", "worlds-greatest"]
        case .kneesCaving: return ["glute-bridge", "side-leg-lift", "single-leg-bridge"]
        case .lateralShift: return ["single-leg-bridge", "reverse-lunge", "single-leg-hinge"]
        }
    }

    var penalty: Int {
        switch self {
        case .limitedOverhead, .shallowSquat, .kneesCaving: return 12
        case .unevenShoulders, .unevenHips, .unevenReach, .lateralShift: return 8
        case .headTilt: return 6
        }
    }
}

struct BodyScanResult: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var metrics: ScanMetrics
    var findings: [ScanFinding]
    var score: Int
    var recommendedExerciseIDs: [String]
    var focusCategories: [MovementCategory]
    /// True for the simulator / no-camera demo result.
    var isSample = false

    func detail(for finding: ScanFinding) -> String {
        func deg(_ v: Double?) -> String { v.map { String(format: "%.0f°", $0) } ?? "–" }
        switch finding {
        case .unevenShoulders: return "One shoulder sits about \(deg(metrics.shoulderTilt)) higher."
        case .unevenHips: return "Hips tilt about \(deg(metrics.hipTilt))."
        case .headTilt: return "Head tilts about \(deg(metrics.headTilt)) off centre."
        case .limitedOverhead:
            let best = max(metrics.reachLeft ?? 0, metrics.reachRight ?? 0)
            return "Arms reached about \(String(format: "%.0f°", best)) of 180°."
        case .unevenReach:
            let diff = abs((metrics.reachLeft ?? 0) - (metrics.reachRight ?? 0))
            return "About \(String(format: "%.0f°", diff)) difference between arms."
        case .shallowSquat:
            return "Hips dropped \(Int(((metrics.squatDepth ?? 0) * 100).rounded()))% of leg length (aim for ~40%+)."
        case .kneesCaving:
            return "Knee gap was \(Int(((metrics.kneeTracking ?? 0) * 100).rounded()))% of foot gap at the bottom."
        case .lateralShift:
            return "Hips moved \(Int(((metrics.lateralShift ?? 0) * 100).rounded()))% of stance width to one side."
        }
    }
}

// MARK: - Analyzer

/// Turns raw measurements into findings, a score and exercise picks. Pure and testable.
enum BodyScanAnalyzer {

    struct Thresholds {
        static let tilt = 3.5           // degrees
        static let headTilt = 6.0       // degrees
        static let reach = 150.0        // degrees
        static let reachDiff = 12.0     // degrees
        static let depth = 0.30         // fraction of leg length
        static let kneeTracking = 0.85  // ratio
        static let shift = 0.18         // fraction of stance width
    }

    static func findings(for m: ScanMetrics) -> [ScanFinding] {
        var out: [ScanFinding] = []
        if let v = m.shoulderTilt, v > Thresholds.tilt { out.append(.unevenShoulders) }
        if let v = m.hipTilt, v > Thresholds.tilt { out.append(.unevenHips) }
        if let v = m.headTilt, v > Thresholds.headTilt { out.append(.headTilt) }
        if let l = m.reachLeft, let r = m.reachRight {
            if max(l, r) < Thresholds.reach { out.append(.limitedOverhead) }
            if abs(l - r) > Thresholds.reachDiff { out.append(.unevenReach) }
        }
        if let d = m.squatDepth, d < Thresholds.depth { out.append(.shallowSquat) }
        if let k = m.kneeTracking, k < Thresholds.kneeTracking { out.append(.kneesCaving) }
        if let s = m.lateralShift, s > Thresholds.shift { out.append(.lateralShift) }
        // Most impactful first.
        return out.sorted { $0.penalty > $1.penalty }
    }

    static func result(for m: ScanMetrics, isSample: Bool = false) -> BodyScanResult {
        let f = findings(for: m)
        let score = max(40, min(100, 100 - f.reduce(0) { $0 + $1.penalty }))

        var exercises: [String] = []
        var focus: [MovementCategory] = []
        let sources = f.isEmpty ? [] : f
        for finding in sources {
            for id in finding.exercises where !exercises.contains(id) { exercises.append(id) }
            for c in finding.focus where !focus.contains(c) { focus.append(c) }
        }
        if f.isEmpty {
            // Moving well: suggest progressions.
            exercises = ["push-up", "reverse-lunge", "forearm-plank", "single-leg-hinge"]
        }
        return BodyScanResult(metrics: m, findings: f, score: score,
                              recommendedExerciseIDs: Array(exercises.prefix(6)),
                              focusCategories: Array(focus.prefix(2)), isSample: isSample)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Demo data for devices without a camera (e.g. the simulator). Clearly marked as a sample.
    static var sampleResult: BodyScanResult {
        result(for: ScanMetrics(shoulderTilt: 4.6, hipTilt: 1.8, headTilt: 3.0, reachLeft: 158, reachRight: 143,
                                squatDepth: 0.36, kneeTracking: 0.79, lateralShift: 0.08, squatReps: 3),
               isSample: true)
    }
}

// MARK: - Live scan controller

/// Drives the three-step scan from live poses: stand tall → arms overhead → 3 squats.
@Observable
final class BodyScanController {

    enum Step: Int, CaseIterable {
        case position, stand, reach, squat, done

        var title: String {
            switch self {
            case .position: return "Step back"
            case .stand: return "Stand tall"
            case .reach: return "Arms up"
            case .squat: return "3 slow squats"
            case .done: return "All done"
            }
        }

        var instruction: String {
            switch self {
            case .position: return "Prop your phone up and step back until your whole body fits in the frame."
            case .stand: return "Feet hip-width, arms relaxed. Hold still for 3 seconds."
            case .reach: return "Raise both arms straight overhead, as high as is comfortable. Hold."
            case .squat: return "Squat down slowly and stand back up, 3 times. Facing the camera."
            case .done: return "Analysing your movement…"
            }
        }
    }

    private(set) var step: Step = .position
    /// Progress within the current step, 0...1.
    private(set) var progress: Double = 0
    private(set) var reps = 0
    private(set) var bodyVisible = false
    private(set) var result: BodyScanResult?

    @ObservationIgnored var onStepChange: ((Step) -> Void)?
    @ObservationIgnored var onRep: ((Int) -> Void)?

    // Collected samples
    @ObservationIgnored private var stepStart = Date()
    @ObservationIgnored private var holdStart: Date?
    @ObservationIgnored private var shoulderTilts: [Double] = []
    @ObservationIgnored private var hipTilts: [Double] = []
    @ObservationIgnored private var headTilts: [Double] = []
    @ObservationIgnored private var reachL: [Double] = []
    @ObservationIgnored private var reachR: [Double] = []
    // Squat state
    @ObservationIgnored private var standingHipY: Double?
    @ObservationIgnored private var legLength: Double?
    @ObservationIgnored private var isDown = false
    @ObservationIgnored private var repMaxDepth = 0.0
    @ObservationIgnored private var repBottomPose: BodyPose?
    @ObservationIgnored private var depths: [Double] = []
    @ObservationIgnored private var kneeRatios: [Double] = []
    @ObservationIgnored private var shifts: [Double] = []

    static let standSeconds = 3.0
    static let reachSeconds = 1.5
    static let reachTimeout = 15.0
    static let squatTimeout = 45.0
    static let targetReps = 3

    func feed(_ pose: BodyPose?, now: Date = Date()) {
        guard step != .done else { return }
        let visible = pose?.isFullBodyVisible ?? false
        bodyVisible = visible

        switch step {
        case .position:
            if visible {
                if holdStart == nil { holdStart = now }
                progress = min(1, now.timeIntervalSince(holdStart!) / 1.0)
                if progress >= 1 { advance(to: .stand, now: now) }
            } else {
                holdStart = nil
                progress = 0
            }

        case .stand:
            guard visible, let pose else { holdStart = nil; progress = 0; return }
            if holdStart == nil { holdStart = now }
            collectStanding(pose)
            progress = min(1, now.timeIntervalSince(holdStart!) / Self.standSeconds)
            if progress >= 1 {
                calibrateSquat(pose)
                advance(to: .reach, now: now)
            }

        case .reach:
            if let pose, pose.armsOverhead {
                if holdStart == nil { holdStart = now }
                if let l = pose.reachAngle(left: true) { reachL.append(l) }
                if let r = pose.reachAngle(left: false) { reachR.append(r) }
                progress = min(1, now.timeIntervalSince(holdStart!) / Self.reachSeconds)
            } else {
                holdStart = nil
                progress = 0
            }
            if progress >= 1 || now.timeIntervalSince(stepStart) > Self.reachTimeout {
                advance(to: .squat, now: now)
            }

        case .squat:
            if let pose, visible { trackSquat(pose) }
            progress = Double(reps) / Double(Self.targetReps)
            if reps >= Self.targetReps || now.timeIntervalSince(stepStart) > Self.squatTimeout {
                finish()
            }

        case .done:
            break
        }
    }

    /// Skip the current step (e.g. the user can't raise their arms).
    func skipStep() {
        switch step {
        case .position: advance(to: .stand, now: Date())
        case .stand: advance(to: .reach, now: Date())
        case .reach: advance(to: .squat, now: Date())
        case .squat: finish()
        case .done: break
        }
    }

    private func advance(to next: Step, now: Date) {
        step = next
        progress = 0
        holdStart = nil
        stepStart = now
        onStepChange?(next)
    }

    private func collectStanding(_ pose: BodyPose) {
        if let ls = pose.g(.leftShoulder), let rs = pose.g(.rightShoulder) {
            shoulderTilts.append(BodyPose.tilt(ls, rs))
        }
        if let lh = pose.g(.leftHip), let rh = pose.g(.rightHip) {
            hipTilts.append(BodyPose.tilt(lh, rh))
        }
        if let le = pose.g(.leftEar), let re = pose.g(.rightEar) {
            headTilts.append(BodyPose.tilt(le, re))
        } else if let leye = pose.g(.leftEye), let reye = pose.g(.rightEye) {
            headTilts.append(BodyPose.tilt(leye, reye))
        }
    }

    private func calibrateSquat(_ pose: BodyPose) {
        guard let lh = pose.g(.leftHip), let rh = pose.g(.rightHip),
              let la = pose.g(.leftAnkle), let ra = pose.g(.rightAnkle) else { return }
        let hip = BodyPose.mid(lh, rh), ankle = BodyPose.mid(la, ra)
        standingHipY = Double(hip.y)
        legLength = Double(ankle.y - hip.y)
    }

    private func trackSquat(_ pose: BodyPose) {
        guard let lh = pose.g(.leftHip), let rh = pose.g(.rightHip),
              let la = pose.g(.leftAnkle), let ra = pose.g(.rightAnkle) else { return }
        let hip = BodyPose.mid(lh, rh), ankle = BodyPose.mid(la, ra)
        if standingHipY == nil || legLength == nil { calibrateSquat(pose) }
        guard let base = standingHipY, let leg = legLength, leg > 0.05 else { return }

        let depth = (Double(hip.y) - base) / leg
        if !isDown {
            if depth > 0.15 {
                isDown = true
                repMaxDepth = depth
                repBottomPose = pose
            } else if depth < 0.03 {
                // Slowly re-calibrate while standing.
                standingHipY = base * 0.9 + Double(hip.y) * 0.1
            }
        } else {
            if depth > repMaxDepth {
                repMaxDepth = depth
                repBottomPose = pose
            }
            if depth < 0.07 {
                isDown = false
                reps += 1
                depths.append(repMaxDepth)
                if let bottom = repBottomPose { measureBottom(bottom) }
                onRep?(reps)
            }
        }
        _ = ankle
    }

    private func measureBottom(_ pose: BodyPose) {
        guard let lk = pose.g(.leftKnee), let rk = pose.g(.rightKnee),
              let la = pose.g(.leftAnkle), let ra = pose.g(.rightAnkle),
              let lh = pose.g(.leftHip), let rh = pose.g(.rightHip) else { return }
        let ankleGap = abs(Double(la.x - ra.x))
        guard ankleGap > 0.02 else { return }
        kneeRatios.append(abs(Double(lk.x - rk.x)) / ankleGap)
        let hipMid = BodyPose.mid(lh, rh), ankleMid = BodyPose.mid(la, ra)
        shifts.append(abs(Double(hipMid.x - ankleMid.x)) / ankleGap)
    }

    private func finish() {
        let metrics = ScanMetrics(
            shoulderTilt: BodyScanAnalyzer.median(shoulderTilts),
            hipTilt: BodyScanAnalyzer.median(hipTilts),
            headTilt: BodyScanAnalyzer.median(headTilts),
            reachLeft: reachL.max(),
            reachRight: reachR.max(),
            squatDepth: depths.max(),
            kneeTracking: BodyScanAnalyzer.median(kneeRatios),
            lateralShift: BodyScanAnalyzer.median(shifts),
            squatReps: reps)
        result = BodyScanAnalyzer.result(for: metrics)
        advance(to: .done, now: Date())
    }
}
