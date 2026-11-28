import Foundation

/// Rule-based workout generator (proposal §2.2, steps 1–6).
/// Pure and deterministic: the same `SetupInput` always produces the same `WorkoutPlan`.
struct WorkoutGenerator {

    var library: [Exercise] = ExerciseLibrary.all

    /// Every slot (exercise + rest) is 60 seconds.
    static let slotSeconds = 60

    // MARK: Step 1 — intensity

    static func timing(forDifficulty difficulty: Int) -> (work: Int, rest: Int) {
        switch difficulty {
        case ...2: return (30, 30)
        case 3: return (40, 20)
        default: return (50, 10)
        }
    }

    /// Reps for a strength move. Harder-than-energy variations get a slightly smaller set.
    static func reps(forDifficulty difficulty: Int, exercise: Exercise) -> Int {
        let base: Int
        switch difficulty {
        case ...2: base = 8
        case 3: base = 10
        default: base = 12
        }
        let harder = max(0, exercise.level - difficulty)
        return max(6, base - harder * 2)
    }

    // MARK: Step 3 — category rotation

    /// push → squat → hinge → core → mobility, minus disabled ones, plus any focus categories repeated at the end.
    func rotation(for input: SetupInput) -> [MovementCategory] {
        var base = MovementCategory.allCases.filter { !input.disabledCategories.contains($0) }
        if base.isEmpty { base = MovementCategory.allCases }
        var extra: [MovementCategory] = []
        for category in input.focus where base.contains(category) && !extra.contains(category) {
            extra.append(category)
        }
        return base + extra
    }

    // MARK: Step 4 — limitations

    /// Returns why an exercise can't be used, or nil if it fits.
    func exclusionReason(for exercise: Exercise, input: SetupInput) -> String? {
        if exercise.isJumping && !input.location.allowsJumping {
            return "\(input.location.title): no jumping"
        }
        if exercise.needsGroundLying && !input.location.allowsGroundLying {
            return "\(input.location.title): no lying or kneeling on the ground"
        }
        let hits = exercise.stresses.intersection(input.discomfort).sorted()
        if !hits.isEmpty {
            return hits.map { $0.title }.joined(separator: ", ") + " discomfort"
        }
        return nil
    }

    func eligible(in category: MovementCategory, input: SetupInput) -> [Exercise] {
        library.filter { $0.category == category && !$0.isRecovery && exclusionReason(for: $0, input: input) == nil }
    }

    // MARK: Step 5 — selection

    /// Lower is better. Prefers unused moves, then the closest level, then scan-recommended moves, then id.
    private func rank(_ exercise: Exercise, difficulty: Int, uses: [String: Int],
                      previousID: String?, preferred: [String]) -> (Int, Int, Int, Int, Int, String) {
        let used = uses[exercise.id, default: 0]
        let repeatsPrevious = exercise.id == previousID ? 1 : 0
        let isPreferred = preferred.contains(exercise.id)
        let distance = abs(exercise.level - difficulty)
        let adjusted = max(0, distance - (isPreferred ? 1 : 0))
        return (used, repeatsPrevious, adjusted, isPreferred ? 0 : 1, distance, exercise.id)
    }

    func pick(from candidates: [Exercise], difficulty: Int, uses: [String: Int],
              previousID: String?, preferred: [String]) -> Exercise? {
        candidates.min { a, b in
            rank(a, difficulty: difficulty, uses: uses, previousID: previousID, preferred: preferred)
                < rank(b, difficulty: difficulty, uses: uses, previousID: previousID, preferred: preferred)
        }
    }

    // MARK: Generate

    func generate(_ rawInput: SetupInput) -> WorkoutPlan {
        var input = rawInput
        input.duration = min(SetupInput.durationRange.upperBound, max(SetupInput.durationRange.lowerBound, input.duration))
        let difficulty = input.difficulty
        let timing = Self.timing(forDifficulty: difficulty)

        var explanation: [String] = []
        var notices: [String] = []

        // Step 1
        explanation.append("Feeling \(input.feeling.title.lowercased()) → \(timing.work)s work / \(timing.rest)s rest per move.")

        // Step 2 — how many slots fit
        let recoveryArea = input.discomfort.sorted().first { area in library.contains { $0.isRecovery && $0.eases == area } }
        let totalSlots = input.duration * 60 / Self.slotSeconds
        let mainSlots = max(1, totalSlots - (recoveryArea == nil ? 0 : 1))
        explanation.append("\(input.duration) min → \(mainSlots) moves" + (recoveryArea == nil ? "." : " + 1 min recovery."))

        // Step 3
        var order = self.rotation(for: input)
        let off = MovementCategory.allCases.filter { input.disabledCategories.contains($0) }
        if !off.isEmpty && off.count < MovementCategory.allCases.count {
            explanation.append("Skipping " + off.map { $0.title.lowercased() }.joined(separator: ", ") + " as you asked.")
        }
        if !input.focus.isEmpty {
            explanation.append("Extra focus on " + input.focus.map { $0.title.lowercased() }.joined(separator: " & ") + ".")
        }

        // Step 4 — record every exclusion once
        var excluded: [ExcludedExercise] = []
        for exercise in library where !exercise.isRecovery && order.contains(exercise.category) {
            if let reason = exclusionReason(for: exercise, input: input) {
                excluded.append(ExcludedExercise(name: exercise.name, reason: reason))
            }
        }
        if !input.location.allowsJumping && library.contains(where: { $0.isJumping }) {
            explanation.append("\(input.location.title) → no jumping moves.")
        }
        if !input.location.allowsGroundLying && library.contains(where: { $0.needsGroundLying }) {
            explanation.append("\(input.location.title) → skipped moves that need you to lie or kneel on the ground.")
        }
        if !input.discomfort.isEmpty {
            explanation.append("Avoiding pressure on " + input.discomfort.sorted().map { $0.title.lowercased() }.joined(separator: ", ") + ".")
        }

        // Drop categories with nothing eligible so the order stays balanced among the rest.
        let usable = order.filter { !eligible(in: $0, input: input).isEmpty }
        for category in Array(Set(order)).sorted(by: { $0.rawValue < $1.rawValue }) where !usable.contains(category) {
            notices.append("No \(category.title.lowercased()) moves fit today, so Ember used other categories instead.")
        }
        order = usable

        // Step 5 — fill slots
        var items: [PlanItem] = []
        var uses: [String: Int] = [:]
        var previousID: String?
        if order.isEmpty {
            notices.append("Nothing in the library fits these limits. Try removing a discomfort area or changing location.")
        } else {
            for slot in 0..<mainSlots {
                let category = order[slot % order.count]
                let candidates = eligible(in: category, input: input)
                guard let chosen = pick(from: candidates, difficulty: difficulty, uses: uses,
                                        previousID: previousID, preferred: input.preferredExercises) else { continue }
                uses[chosen.id, default: 0] += 1
                previousID = chosen.id
                items.append(PlanItem(id: items.count, exerciseID: chosen.id,
                                      workSeconds: timing.work, restSeconds: timing.rest,
                                      isRecovery: false,
                                      reason: reason(for: chosen, category: category, difficulty: difficulty, input: input),
                                      targetReps: chosen.countsByReps ? Self.reps(forDifficulty: difficulty, exercise: chosen) : nil))
            }
        }

        // Step 6 — optional recovery
        if let area = recoveryArea, let ease = library.first(where: { $0.isRecovery && $0.eases == area }), !items.isEmpty {
            items.append(PlanItem(id: items.count, exerciseID: ease.id, workSeconds: Self.slotSeconds, restSeconds: 0,
                                  isRecovery: true, reason: "Optional. A gentle way to ease your \(area.title.lowercased()). Not medical advice."))
            explanation.append("Added \(ease.name) (60s) at the end. Skip it anytime.")
        }

        if items.contains(where: { $0.isRepWork }) {
            explanation.append("Strength moves are counted in reps; holds, mobility and cardio stay on a timer.")
        }

        return WorkoutPlan(input: input, items: items, explanation: explanation, excluded: excluded, notices: notices)
    }

    private func reason(for exercise: Exercise, category: MovementCategory, difficulty: Int, input: SetupInput) -> String {
        if input.preferredExercises.contains(exercise.id) { return "Picked from your body scan" }
        if input.focus.contains(category) { return "\(category.title) focus" }
        let diff = exercise.level - difficulty
        if diff == 0 { return "\(category.title) · matches your energy" }
        return diff < 0 ? "\(category.title) · a little easier" : "\(category.title) · a little harder"
    }

    // MARK: Replace

    /// Same-category alternatives for an item that still respect location and discomfort.
    func alternatives(for item: PlanItem, in plan: WorkoutPlan) -> [Exercise] {
        let current = item.exercise
        if item.isRecovery {
            return library.filter { candidate in
                guard candidate.isRecovery, candidate.id != current.id, let area = candidate.eases else { return false }
                return plan.input.discomfort.contains(area)
            }
        }
        let difficulty = plan.input.difficulty
        return eligible(in: current.category, input: plan.input)
            .filter { $0.id != current.id }
            .sorted { (abs($0.level - difficulty), $0.id) < (abs($1.level - difficulty), $1.id) }
    }

    func replacing(_ item: PlanItem, with exercise: Exercise, in plan: WorkoutPlan) -> WorkoutPlan {
        var copy = plan
        if let index = copy.items.firstIndex(where: { $0.id == item.id }) {
            copy.items[index].exerciseID = exercise.id
            copy.items[index].reason = "Swapped in by you"
            copy.items[index].targetReps = exercise.countsByReps
                ? Self.reps(forDifficulty: plan.input.difficulty, exercise: exercise)
                : nil
        }
        return copy
    }
}
