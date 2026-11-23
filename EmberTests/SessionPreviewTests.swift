import XCTest
@testable import Ember

@MainActor
final class SessionPreviewTests: XCTestCase {
    func testPreviewHoldsAThirtySecondBoutUntilItIsSkipped() {
        var engine = SessionEngine(items: [item(id: "squat", work: 30, rest: 10)])
        var gate = PreviewGate()
        for _ in 0..<5 {
            tickIfReady(&engine, gate: gate)
        }
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.remaining, 30)
        XCTAssertEqual(engine.records[0].result, .skipped)
        XCTAssertTrue(gate.isPreviewing(phase: engine.phase, index: engine.index))

        gate.acknowledge(index: 0)
        XCTAssertFalse(gate.isPreviewing(phase: engine.phase, index: engine.index))
        tickIfReady(&engine, gate: gate)
        XCTAssertEqual(engine.remaining, 29)
        XCTAssertEqual(engine.phase, .work)
    }

    func testEndingDuringPreviewRecordsNoWork() {
        var engine = SessionEngine(items: [item(id: "squat", work: 30, rest: 10)])
        let gate = PreviewGate()
        XCTAssertTrue(gate.isPreviewing(phase: engine.phase, index: engine.index))
        engine.endEarly()
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.status, .stopped)
        XCTAssertEqual(engine.records[0].result, .skipped)
        XCTAssertEqual(engine.records[0].elapsedSec, 0)
    }

    func testRestKeepsTickingAndTheNextExerciseWaitsAtFullTime() {
        var engine = SessionEngine(items: [
            item(id: "push-up", work: 2, rest: 1),
            item(id: "squat", work: 30, rest: 10)
        ])
        var gate = PreviewGate()
        gate.acknowledge(index: 0)
        tickIfReady(&engine, gate: gate)
        tickIfReady(&engine, gate: gate)
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertFalse(gate.isPreviewing(phase: engine.phase, index: engine.index))
        tickIfReady(&engine, gate: gate)
        XCTAssertEqual(engine.index, 1)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.remaining, 30)
        XCTAssertTrue(gate.isPreviewing(phase: engine.phase, index: engine.index))
        tickIfReady(&engine, gate: gate)
        XCTAssertEqual(engine.remaining, 30)
    }

    func testSkippingTheExercisePreviewsTheNextOne() {
        var engine = SessionEngine(items: [
            item(id: "push-up", work: 30, rest: 10),
            item(id: "squat", work: 30, rest: 0)
        ])
        var gate = PreviewGate()
        gate.acknowledge(index: 0)
        engine.tick()
        engine.skip()
        XCTAssertEqual(engine.index, 1)
        XCTAssertEqual(engine.remaining, 30)
        XCTAssertEqual(engine.records[0].result, .skipped)
        XCTAssertTrue(gate.isPreviewing(phase: engine.phase, index: engine.index))
    }

    func testPreviewNamesStayInsideTheBundle() {
        var expected = Set(ExerciseLibrary.all.map(\.id))
        expected.insert("self-massage")
        expected.insert(ExercisePreviewCatalog.fallbackResource)
        XCTAssertEqual(ExercisePreviewCatalog.knownIds, expected)
        for id in ExercisePreviewCatalog.knownIds {
            XCTAssertEqual(ExercisePreviewCatalog.resourceName(for: id), id)
            XCTAssertFalse(id.contains("/"))
            XCTAssertFalse(id.contains(":"))
        }
        XCTAssertEqual(ExercisePreviewCatalog.resourceName(for: "not-a-move"), ExercisePreviewCatalog.fallbackResource)
        let url = ExercisePreviewCatalog.url(for: "squat", bundle: Bundle(for: SessionPreviewTests.self))
        XCTAssertNil(url)
    }

    func testSquatDepthStandingAndKnees() {
        let depth = FormEvaluator.evaluate(exerciseId: "squat", joints: pose([
            (.leftShoulder, 0.40, 0.85),
            (.leftHip, 0.40, 0.70),
            (.leftKnee, 0.40, 0.45),
            (.leftAnkle, 0.65, 0.45)
        ]))
        XCTAssertEqual(depth.tone, .good)
        XCTAssertEqual(depth.title, "Depth looks right.")
        XCTAssertEqual(depth.detail, "Knee 90° · bottom is under 115°")

        let standing = FormEvaluator.evaluate(exerciseId: "sit-to-stand", joints: pose([
            (.leftShoulder, 0.50, 0.90),
            (.leftHip, 0.50, 0.75),
            (.leftKnee, 0.50, 0.50),
            (.leftAnkle, 0.50, 0.25)
        ]))
        XCTAssertEqual(standing.tone, .good)
        XCTAssertEqual(standing.title, "Standing tall.")
        XCTAssertEqual(standing.detail, "Knee 180° · top is a straight leg")

        let lowering = FormEvaluator.evaluate(exerciseId: "jump-squat", joints: pose([
            (.leftShoulder, 0.42, 0.85),
            (.leftHip, 0.40, 0.70),
            (.leftKnee, 0.50, 0.45),
            (.leftAnkle, 0.40, 0.20)
        ]))
        XCTAssertEqual(lowering.tone, .guide)
        XCTAssertEqual(lowering.title, "Sit the hips back as you lower.")
        XCTAssertTrue(lowering.detail.hasPrefix("Knee 136°"))

        let caving = FormEvaluator.evaluate(exerciseId: "squat", joints: pose([
            (.leftShoulder, 0.40, 0.85),
            (.rightShoulder, 0.60, 0.85),
            (.leftHip, 0.42, 0.70),
            (.rightHip, 0.58, 0.70),
            (.leftKnee, 0.48, 0.48),
            (.rightKnee, 0.52, 0.48),
            (.leftAnkle, 0.30, 0.22),
            (.rightAnkle, 0.70, 0.22)
        ]))
        XCTAssertEqual(caving.tone, .adjust)
        XCTAssertEqual(caving.title, "Push the knees out over the toes.")
    }

    func testPushUpLineAndKneePushUpIgnoresALiftedAnkle() {
        let straight = FormEvaluator.evaluate(exerciseId: "push-up", joints: pose([
            (.leftShoulder, 0.25, 0.55),
            (.leftElbow, 0.25, 0.40),
            (.leftWrist, 0.25, 0.20),
            (.leftHip, 0.50, 0.55),
            (.leftAnkle, 0.80, 0.55)
        ]))
        XCTAssertEqual(straight.title, "Arms are straight.")
        XCTAssertEqual(straight.detail, "Elbow 180° · arms straight at the top")

        let bottom = FormEvaluator.evaluate(exerciseId: "wall-push-up", joints: pose([
            (.leftShoulder, 0.25, 0.55),
            (.leftElbow, 0.40, 0.40),
            (.leftWrist, 0.55, 0.55),
            (.leftHip, 0.50, 0.55),
            (.leftAnkle, 0.80, 0.55)
        ]))
        XCTAssertEqual(bottom.tone, .good)
        XCTAssertEqual(bottom.title, "Chest and body line look right.")
        XCTAssertEqual(bottom.detail, "Elbow 90° · chest toward the floor")

        let pike = FormEvaluator.evaluate(exerciseId: "push-up", joints: pose([
            (.leftShoulder, 0.20, 0.40),
            (.leftElbow, 0.35, 0.25),
            (.leftWrist, 0.50, 0.40),
            (.leftHip, 0.50, 0.70),
            (.leftAnkle, 0.80, 0.40)
        ]))
        XCTAssertEqual(pike.tone, .adjust)
        XCTAssertEqual(pike.title, "Keep a straight line from head to heels.")
        XCTAssertEqual(pike.detail, "Body 90° · head, hips, and heels in one line")

        let kneePush = FormEvaluator.evaluate(exerciseId: "knee-push-up", joints: pose([
            (.leftShoulder, 0.30, 0.50),
            (.leftElbow, 0.45, 0.35),
            (.leftWrist, 0.60, 0.50),
            (.leftHip, 0.55, 0.50),
            (.leftKnee, 0.80, 0.50),
            (.leftAnkle, 0.70, 0.20)
        ]))
        XCTAssertEqual(kneePush.tone, .good)
        XCTAssertEqual(kneePush.title, "Chest and body line look right.")
    }

    func testPlankBridgeHingeAndLunge() {
        let plank = FormEvaluator.evaluate(exerciseId: "plank", joints: pose([
            (.leftShoulder, 0.20, 0.50),
            (.leftHip, 0.50, 0.50),
            (.leftKnee, 0.65, 0.50),
            (.leftAnkle, 0.80, 0.50)
        ]))
        XCTAssertEqual(plank.tone, .good)
        XCTAssertEqual(plank.title, "Body line looks straight.")
        XCTAssertEqual(plank.detail, "Body 180° · head to heels")

        let sag = FormEvaluator.evaluate(exerciseId: "plank", joints: pose([
            (.leftShoulder, 0.20, 0.50),
            (.leftHip, 0.50, 0.75),
            (.leftKnee, 0.65, 0.60),
            (.leftAnkle, 0.80, 0.50)
        ]))
        XCTAssertEqual(sag.tone, .adjust)
        XCTAssertEqual(sag.title, "Lengthen into a straight line.")

        let climber = FormEvaluator.evaluate(exerciseId: "mountain-climber", joints: pose([
            (.leftShoulder, 0.20, 0.50),
            (.leftHip, 0.50, 0.50),
            (.leftKnee, 0.65, 0.50),
            (.leftAnkle, 0.80, 0.50)
        ]))
        XCTAssertEqual(climber.tone, .guide)
        XCTAssertEqual(climber.title, "Drive one knee in, then the other.")

        let bridge = FormEvaluator.evaluate(exerciseId: "glute-bridge", joints: pose([
            (.leftShoulder, 0.20, 0.50),
            (.leftHip, 0.50, 0.50),
            (.leftKnee, 0.80, 0.50),
            (.leftAnkle, 0.70, 0.70)
        ]))
        XCTAssertEqual(bridge.tone, .good)
        XCTAssertEqual(bridge.title, "Hips are up.")
        XCTAssertEqual(bridge.detail, "Hip 180° · hips open at the top")

        let lowBridge = FormEvaluator.evaluate(exerciseId: "glute-bridge", joints: pose([
            (.leftShoulder, 0.20, 0.40),
            (.leftHip, 0.50, 0.40),
            (.leftKnee, 0.50, 0.70),
            (.leftAnkle, 0.70, 0.70)
        ]))
        XCTAssertEqual(lowBridge.tone, .adjust)
        XCTAssertEqual(lowBridge.title, "Press the hips a little higher.")
        XCTAssertEqual(lowBridge.detail, "Hip 90° · press the hips up")

        let hinge = FormEvaluator.evaluate(exerciseId: "hip-hinge", joints: pose([
            (.leftShoulder, 0.20, 0.42),
            (.leftHip, 0.55, 0.50),
            (.leftKnee, 0.48, 0.70),
            (.leftAnkle, 0.46, 0.90)
        ]))
        XCTAssertEqual(hinge.tone, .good)
        XCTAssertEqual(hinge.title, "Hinge looks right.")

        let squattyHinge = FormEvaluator.evaluate(exerciseId: "single-leg-hinge", joints: pose([
            (.leftShoulder, 0.40, 0.80),
            (.leftHip, 0.40, 0.70),
            (.leftKnee, 0.40, 0.45),
            (.leftAnkle, 0.65, 0.45)
        ]))
        XCTAssertEqual(squattyHinge.tone, .adjust)
        XCTAssertEqual(squattyHinge.title, "Soften the knees only. Hinge at the hips.")

        let lunge = FormEvaluator.evaluate(exerciseId: "reverse-lunge", joints: pose([
            (.leftShoulder, 0.40, 0.85),
            (.leftHip, 0.40, 0.70),
            (.leftKnee, 0.40, 0.45),
            (.leftAnkle, 0.65, 0.45)
        ]))
        XCTAssertEqual(lunge.tone, .good)
        XCTAssertEqual(lunge.detail, "Knee 90° · front thigh about level")

        let crashed = FormEvaluator.evaluate(exerciseId: "reverse-lunge", joints: pose([
            (.leftShoulder, 0.40, 0.70),
            (.leftHip, 0.40, 0.50),
            (.leftKnee, 0.50, 0.50),
            (.leftAnkle, 0.48, 0.52)
        ]))
        XCTAssertEqual(crashed.tone, .adjust)
        XCTAssertEqual(crashed.title, "Don't drop the back knee into the floor.")
    }

    func testMissingPersonAndMovesWithoutAnAngleRule() {
        XCTAssertEqual(FormEvaluator.evaluate(exerciseId: "squat", joints: [:]), .noPerson)
        let faint = pose(PoseJoint.allCases.map { ($0, 0.5, 0.5) }, confidence: 0.1)
        XCTAssertEqual(FormEvaluator.evaluate(exerciseId: "push-up", joints: faint), .noPerson)

        let partial = pose([
            (.nose, 0.5, 0.9),
            (.leftShoulder, 0.4, 0.8),
            (.rightShoulder, 0.6, 0.8),
            (.leftElbow, 0.3, 0.7)
        ])
        XCTAssertEqual(FormEvaluator.evaluate(exerciseId: "squat", joints: partial), .incomplete)

        let body = pose([
            (.leftShoulder, 0.40, 0.85),
            (.leftHip, 0.40, 0.70),
            (.leftKnee, 0.40, 0.45),
            (.leftAnkle, 0.65, 0.45)
        ])
        XCTAssertEqual(FormEvaluator.evaluate(exerciseId: "dead-bug", joints: body), .guideOnly)
        XCTAssertEqual(FormEvaluator.evaluate(exerciseId: "self-massage", joints: body), .guideOnly)
        XCTAssertEqual(
            FormEvaluator.reference(for: "squat"),
            "Reference: sit the hips back, knees over the toes."
        )
        XCTAssertEqual(
            FormEvaluator.reference(for: "push-up"),
            "Reference: straight body, chest toward the floor."
        )
        XCTAssertEqual(
            FormEvaluator.reference(for: "open-book"),
            "Reference: follow the cue. This check draws your outline."
        )
    }

    private func tickIfReady(_ engine: inout SessionEngine, gate: PreviewGate) {
        guard !gate.isPreviewing(phase: engine.phase, index: engine.index) else { return }
        engine.tick()
    }

    private func item(id: String, work: Int, rest: Int) -> PlanItem {
        PlanItem(
            id: id,
            exerciseId: id,
            name: id,
            pattern: .squat,
            workSec: work,
            restSec: rest,
            cue: "Cue",
            isSelfMassage: false
        )
    }

    private func pose(_ values: [(PoseJoint, Double, Double)], confidence: Double = 0.95) -> [PoseJoint: PosePoint] {
        var joints: [PoseJoint: PosePoint] = [:]
        for (joint, x, y) in values {
            joints[joint] = PosePoint(x: x, y: y, confidence: confidence)
        }
        return joints
    }
}
