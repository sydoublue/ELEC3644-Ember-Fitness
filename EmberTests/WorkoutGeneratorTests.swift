import XCTest
@testable import Ember

/// The proposal requires selection to stay "a testable rule engine" where
/// "the same inputs always produce the same workout plan". These tests pin that down.
final class WorkoutGeneratorTests: XCTestCase {

    let generator = WorkoutGenerator()

    // Step 1 — intensity
    func testTimingByDifficulty() {
        XCTAssertEqual(WorkoutGenerator.timing(forDifficulty: 1).work, 30)
        XCTAssertEqual(WorkoutGenerator.timing(forDifficulty: 2).rest, 30)
        XCTAssertEqual(WorkoutGenerator.timing(forDifficulty: 3).work, 40)
        XCTAssertEqual(WorkoutGenerator.timing(forDifficulty: 3).rest, 20)
        XCTAssertEqual(WorkoutGenerator.timing(forDifficulty: 5).work, 50)
        XCTAssertEqual(WorkoutGenerator.timing(forDifficulty: 5).rest, 10)
    }

    // Step 2 — length
    func testSlotsFitDuration() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10))
        XCTAssertEqual(plan.items.count, 10)
        XCTAssertTrue(plan.items.allSatisfy { $0.totalSeconds == 60 })
    }

    func testDiscomfortReservesLastMinuteForRecovery() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10, discomfort: [.knees]))
        XCTAssertEqual(plan.mainItems.count, 9)
        XCTAssertEqual(plan.items.last?.exerciseID, "knee-ease")
        XCTAssertEqual(plan.items.last?.isRecovery, true)
    }

    // Step 3 — rotation
    func testCategoryRotation() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10))
        let cats = plan.items.map { $0.exercise.category }
        XCTAssertEqual(Array(cats.prefix(5)), [.push, .squat, .hinge, .core, .mobility])
    }

    func testDisabledCategoryIsSkipped() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10, disabledCategories: [.push]))
        XCTAssertFalse(plan.items.contains { $0.exercise.category == .push })
    }

    // Step 4 — limitations
    func testDormHasNoJumping() {
        for loc in [Location.dorm, .hotel] {
            let plan = generator.generate(SetupInput(feeling: .great, duration: 30, location: loc))
            XCTAssertFalse(plan.items.contains { $0.exercise.isJumping }, "\(loc) should not include jumping")
        }
    }

    func testKneeDiscomfortRemovesSquatsLungesJumps() {
        let plan = generator.generate(SetupInput(feeling: .good, duration: 30, discomfort: [.knees]))
        let ids = Set(plan.items.map(\.exerciseID))
        for banned in ["bodyweight-squat", "reverse-lunge", "jump-squat", "jumping-jacks", "split-squat", "wall-sit"] {
            XCTAssertFalse(ids.contains(banned), "\(banned) should be excluded for knees")
        }
        XCTAssertTrue(plan.mainItems.allSatisfy { !$0.exercise.stresses.contains(.knees) })
        XCTAssertTrue(plan.excluded.contains { $0.name == "Bodyweight squat" })
    }

    func testCategoryWithNothingEligibleFallsBack() {
        // Wrists rule out every push move → the push slot moves to another category with a notice.
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10, discomfort: [.wrists]))
        XCTAssertFalse(plan.mainItems.contains { $0.exercise.category == .push })
        XCTAssertFalse(plan.notices.isEmpty)
        XCTAssertEqual(plan.mainItems.count, 9)
    }

    // Step 5 — selection
    func testDifficultyMatchesLevel() {
        let easy = generator.generate(SetupInput(feeling: .veryLow, duration: 5))
        let hard = generator.generate(SetupInput(feeling: .great, duration: 5))
        let easyAvg = Double(easy.items.map { $0.exercise.level }.reduce(0, +)) / Double(easy.items.count)
        let hardAvg = Double(hard.items.map { $0.exercise.level }.reduce(0, +)) / Double(hard.items.count)
        XCTAssertLessThan(easyAvg, hardAvg)
    }

    func testAvoidsRepeatsWhenPossible() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 15))
        let ids = plan.items.map(\.exerciseID)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testNoBackToBackRepeatsInLongWorkouts() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 30, location: .dorm, discomfort: [.knees, .wrists]))
        for (a, b) in zip(plan.items, plan.items.dropFirst()) {
            XCTAssertNotEqual(a.exerciseID, b.exerciseID)
        }
    }

    // Step 6 — determinism
    func testSameInputSamePlan() {
        let input = SetupInput(feeling: .good, duration: 17, location: .hotel, discomfort: [.lowerBack, .shoulders])
        XCTAssertEqual(generator.generate(input), generator.generate(input))
    }

    // Replace
    func testAlternativesRespectLimits() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10, location: .dorm, discomfort: [.knees]))
        guard let item = plan.mainItems.first else { return XCTFail("empty plan") }
        let alts = generator.alternatives(for: item, in: plan)
        XCTAssertTrue(alts.allSatisfy { $0.category == item.exercise.category && !$0.isJumping && !$0.stresses.contains(.knees) })
    }

    // Feedback bias
    func testFeedbackAdjustsDifficulty() {
        let hard = Feedback(date: Date(), rating: .tooHard, discomfort: [], difficultyUsed: 3)
        let easy = Feedback(date: Date(), rating: .tooEasy, discomfort: [], difficultyUsed: 5)
        XCTAssertEqual(hard.suggestedNextDifficulty, 2)
        XCTAssertEqual(easy.suggestedNextDifficulty, 5)
    }

    func testStoreRemembersSetupAndFeedback() {
        let store = EmberStore(inMemory: true)
        store.rememberSetup(SetupInput(feeling: .good, duration: 20, location: .dorm))
        store.save(feedback: Feedback(date: Date(), rating: .tooHard, discomfort: [.knees], difficultyUsed: 4))
        let next = store.suggestedSetup()
        XCTAssertEqual(next.duration, 20)
        XCTAssertEqual(next.feeling, .okay)
        XCTAssertEqual(next.discomfort, [.knees])
    }

    func testStrengthMovesUseRepsAndHoldsStayTimed() {
        XCTAssertEqual(ExerciseLibrary.exercise("push-up")?.countsByReps, true)
        XCTAssertEqual(ExerciseLibrary.exercise("bodyweight-squat")?.countsByReps, true)
        XCTAssertEqual(ExerciseLibrary.exercise("glute-bridge")?.countsByReps, true)
        XCTAssertEqual(ExerciseLibrary.exercise("forearm-plank")?.countsByReps, false)
        XCTAssertEqual(ExerciseLibrary.exercise("wall-sit")?.countsByReps, false)
        XCTAssertEqual(ExerciseLibrary.exercise("jumping-jacks")?.countsByReps, false)
        XCTAssertEqual(ExerciseLibrary.exercise("knee-ease")?.countsByReps, false)
    }

    func testRepPrescriptionScalesWithDifficultyAndKeepsSixtySecondSlots() {
        let easyPush = ExerciseLibrary.exercise("wall-push-up")!
        let hardPush = ExerciseLibrary.exercise("decline-push-up")!
        XCTAssertEqual(WorkoutGenerator.reps(forDifficulty: 2, exercise: easyPush), 8)
        XCTAssertEqual(WorkoutGenerator.reps(forDifficulty: 5, exercise: easyPush), 12)
        XCTAssertGreaterThanOrEqual(WorkoutGenerator.reps(forDifficulty: 2, exercise: hardPush), 6)
        XCTAssertLessThan(WorkoutGenerator.reps(forDifficulty: 2, exercise: hardPush), 8)

        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10))
        XCTAssertTrue(plan.items.allSatisfy { $0.totalSeconds == 60 })
        let repItems = plan.items.filter(\.isRepWork)
        XCTAssertFalse(repItems.isEmpty)
        XCTAssertTrue(repItems.allSatisfy { ($0.targetReps ?? 0) >= 6 })
        XCTAssertTrue(plan.items.filter { !$0.exercise.countsByReps }.allSatisfy { $0.targetReps == nil })
        XCTAssertTrue(plan.explanation.contains { $0.contains("reps") })
    }

    func testReplacingUpdatesRepTargets() {
        let plan = generator.generate(SetupInput(feeling: .okay, duration: 10))
        guard let item = plan.mainItems.first(where: { $0.exercise.category == .push }) else {
            return XCTFail("expected a push slot")
        }
        guard let plank = ExerciseLibrary.exercise("forearm-plank") else {
            return XCTFail("missing forearm-plank")
        }
        let timed = generator.replacing(item, with: plank, in: plan)
        let swapped = timed.items.first { $0.id == item.id }
        XCTAssertEqual(swapped?.exerciseID, "forearm-plank")
        XCTAssertNil(swapped?.targetReps)
        XCTAssertEqual(swapped?.totalSeconds, 60)

        guard let push = ExerciseLibrary.exercise("push-up") else {
            return XCTFail("missing push-up")
        }
        let counted = generator.replacing(timed.items.first { $0.id == item.id }!, with: push, in: timed)
        let restored = counted.items.first { $0.id == item.id }
        XCTAssertEqual(restored?.exerciseID, "push-up")
        XCTAssertEqual(restored?.targetReps, WorkoutGenerator.reps(forDifficulty: plan.input.difficulty, exercise: push))
    }
}

final class CoachAndScanTests: XCTestCase {

    func testIntentParsing() {
        let i = IntentParser.parse("I have 15 minutes in my dorm, I'm tired and my knees hurt")
        XCTAssertEqual(i.minutes, 15)
        XCTAssertEqual(i.location, .dorm)
        XCTAssertEqual(i.feeling, .low)
        XCTAssertEqual(i.discomfort, [.knees])
        XCTAssertTrue(i.wantsWorkout)
    }

    func testIntentExerciseQuestion() {
        let i = IntentParser.parse("How do I do a wall push up?")
        XCTAssertEqual(i.exerciseID, "wall-push-up")
        XCTAssertFalse(i.wantsWorkout)
    }

    func testScanFindings() {
        let m = ScanMetrics(shoulderTilt: 6, hipTilt: 1, headTilt: 2, reachLeft: 140, reachRight: 165,
                            squatDepth: 0.2, kneeTracking: 0.7, lateralShift: 0.05, squatReps: 3)
        let r = BodyScanAnalyzer.result(for: m)
        XCTAssertTrue(r.findings.contains(.unevenShoulders))
        XCTAssertTrue(r.findings.contains(.unevenReach))
        XCTAssertTrue(r.findings.contains(.shallowSquat))
        XCTAssertTrue(r.findings.contains(.kneesCaving))
        XCTAssertFalse(r.findings.contains(.unevenHips))
        XCTAssertLessThan(r.score, 100)
        XCTAssertFalse(r.recommendedExerciseIDs.isEmpty)
        XCTAssertTrue(r.recommendedExerciseIDs.allSatisfy { ExerciseLibrary.exercise($0) != nil })
    }

    func testLibraryIsConsistent() {
        XCTAssertEqual(Set(ExerciseLibrary.all.map(\.id)).count, ExerciseLibrary.all.count, "duplicate ids")
        for area in BodyArea.allCases {
            XCTAssertNotNil(ExerciseLibrary.recovery(for: area), "no recovery for \(area)")
        }
        for cat in MovementCategory.allCases {
            XCTAssertFalse(ExerciseLibrary.regular(in: cat).isEmpty)
        }
    }
}

@MainActor
final class SessionPlayerTests: XCTestCase {

    func testRepWorkIgnoresTheTimerAndFinishesOnTheLastRep() {
        let plan = WorkoutGenerator().generate(SetupInput(feeling: .okay, duration: 5))
        guard let first = plan.items.first, first.isRepWork, first.restSeconds > 0 else {
            return XCTFail("expected a counted first exercise with rest")
        }
        let player = SessionPlayer(plan: plan)
        player.skipExercise()
        XCTAssertEqual(player.phase, .work)
        XCTAssertTrue(player.isRepWork)
        XCTAssertEqual(player.loggedReps, 0)
        let remaining = player.remaining
        player.tick()
        XCTAssertEqual(player.phase, .work)
        XCTAssertEqual(player.remaining, remaining)
        XCTAssertEqual(player.loggedReps, 0)

        for _ in 1..<player.targetReps {
            player.logRep()
        }
        XCTAssertEqual(player.phase, .work)
        XCTAssertEqual(player.loggedReps, player.targetReps - 1)
        player.logRep()
        XCTAssertEqual(player.phase, .rest)
        XCTAssertEqual(player.results.first?.status, .completed)
        XCTAssertEqual(player.results.first?.completedReps, first.targetReps)
    }

    func testFinishingASetEarlyRecordsTheRepsLogged() {
        let plan = WorkoutGenerator().generate(SetupInput(feeling: .okay, duration: 5))
        guard plan.items.first?.isRepWork == true else {
            return XCTFail("expected a counted first exercise")
        }
        let player = SessionPlayer(plan: plan)
        player.skipExercise()
        player.logRep()
        player.logRep()
        player.completeCurrentExercise()
        XCTAssertEqual(player.results.first?.status, .completed)
        XCTAssertEqual(player.results.first?.completedReps, 2)
    }
}
