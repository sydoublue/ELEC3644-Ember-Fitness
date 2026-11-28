import Foundation

// MARK: - Setup

/// The user's choices for one workout (proposal §2.1).
struct SetupInput: Codable, Hashable {
    var feeling: Feeling = .okay
    /// Minutes, 5...30.
    var duration: Int = 10
    var location: Location = .home
    var discomfort: Set<BodyArea> = []
    /// Categories the user switched off.
    var disabledCategories: Set<MovementCategory> = []
    /// Categories to emphasise (set by Body Scan or Coach).
    var focus: [MovementCategory] = []
    /// Exercises to prefer when they fit (set by Body Scan).
    var preferredExercises: [String] = []

    static let durationRange = 5...30

    var difficulty: Int { feeling.difficulty }
}

// MARK: - Plan

/// One slot in a generated workout.
struct PlanItem: Identifiable, Codable, Hashable {
    /// Position in the plan. Deterministic so identical inputs give identical plans.
    var id: Int
    var exerciseID: String
    var workSeconds: Int
    var restSeconds: Int
    var isRecovery: Bool
    /// Why this exercise is here (shown in the plan preview).
    var reason: String?
    /// When set, the set is completed by repetitions rather than a work timer.
    var targetReps: Int? = nil

    var exercise: Exercise { ExerciseLibrary.exercise(exerciseID) ?? ExerciseLibrary.all[0] }
    var totalSeconds: Int { workSeconds + restSeconds }
    var isRepWork: Bool { (targetReps ?? 0) > 0 }

    var workLabel: String {
        guard let reps = targetReps else { return "\(workSeconds)s work" }
        return exercise.perSide ? "\(reps) each side" : "\(reps) reps"
    }
}

/// The output of `WorkoutGenerator` (proposal §2.2).
struct WorkoutPlan: Codable, Hashable, Identifiable {
    var input: SetupInput
    var items: [PlanItem]
    /// Human-readable explanation of how the plan was built.
    var explanation: [String]
    /// Exercises removed by rules, with the reason, e.g. ("Jump squat", "Dorm: no jumping").
    var excluded: [ExcludedExercise]
    /// Non-blocking notices, e.g. "No push moves fit your wrists — swapped in core."
    var notices: [String]

    var id: Int { hashValue }
    var workSecondsPerItem: Int { items.first(where: { !$0.isRecovery })?.workSeconds ?? 0 }
    var restSecondsPerItem: Int { items.first(where: { !$0.isRecovery })?.restSeconds ?? 0 }

    /// Total planned time including rests (the last rest is not played).
    var totalSeconds: Int {
        let sum = items.reduce(0) { $0 + $1.totalSeconds }
        return max(0, sum - (items.last?.restSeconds ?? 0))
    }

    var mainItems: [PlanItem] { items.filter { !$0.isRecovery } }
    var recoveryItem: PlanItem? { items.first { $0.isRecovery } }

    var title: String {
        "\(input.duration)-min \(input.feeling.title.lowercased()) session"
    }
}

struct ExcludedExercise: Codable, Hashable {
    var name: String
    var reason: String
}

// MARK: - Session

enum ItemStatus: String, Codable, Hashable {
    case completed, skipped
}

struct SessionItemResult: Codable, Hashable {
    var exerciseID: String
    var status: ItemStatus
    var activeSeconds: Int
    var isRecovery: Bool
    var completedReps: Int? = nil
}

/// What actually happened during a workout (proposal §2.3, §4).
struct Session: Identifiable, Codable, Hashable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date
    var input: SetupInput
    var results: [SessionItemResult]
    var skippedBreaks: Int
    var extendedBreaks: Int

    var elapsedSeconds: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }
    var activeSeconds: Int { results.reduce(0) { $0 + $1.activeSeconds } }
    var completedCount: Int { results.filter { $0.status == .completed }.count }
    var skippedCount: Int { results.filter { $0.status == .skipped }.count }
}

// MARK: - Feedback

/// Post-workout reaction that biases the next setup (proposal §2.4).
struct Feedback: Identifiable, Codable, Hashable {
    var id = UUID()
    var sessionID: UUID?
    var date: Date
    var rating: DifficultyRating
    var discomfort: Set<BodyArea>
    var difficultyUsed: Int

    var suggestedNextDifficulty: Int {
        min(5, max(1, difficultyUsed + rating.adjustment))
    }
}

// MARK: - Activity log

/// One entry in the shared chronological log (proposal §2.5).
struct Activity: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var title: String
    var minutes: Int
    var kind: ActivityKind
    /// Free-text type when kind == .other.
    var customKind: String?
    var origin: ActivityOrigin
    var notes: String?
    var sessionID: UUID?
    /// 1...5 perceived effort (optional for outside activities).
    var effort: Int?

    var displayKind: String {
        if kind == .other, let custom = customKind, !custom.isEmpty { return custom }
        return kind.title
    }
}
