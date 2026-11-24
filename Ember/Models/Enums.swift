import Foundation

/// How the user feels today. The raw value doubles as the workout difficulty (1...5).
enum Feeling: Int, Codable, CaseIterable, Identifiable, Hashable {
    case veryLow = 1, low, okay, good, great

    var id: Int { rawValue }
    var difficulty: Int { rawValue }

    var title: String {
        switch self {
        case .veryLow: return "Very low"
        case .low: return "Low"
        case .okay: return "Okay"
        case .good: return "Good"
        case .great: return "Great"
        }
    }

    var emoji: String {
        switch self {
        case .veryLow: return "😮‍💨"
        case .low: return "🙂"
        case .okay: return "😌"
        case .good: return "😀"
        case .great: return "🔥"
        }
    }

    var subtitle: String {
        switch self {
        case .veryLow: return "Gentle moves, long breaks"
        case .low: return "Easy pace"
        case .okay: return "Balanced effort"
        case .good: return "Push a little"
        case .great: return "Bring the heat"
        }
    }

    static func from(difficulty: Int) -> Feeling {
        Feeling(rawValue: min(5, max(1, difficulty))) ?? .okay
    }
}

/// Where the user is exercising. Dorm / hotel exclude jumping moves.
enum Location: String, Codable, CaseIterable, Identifiable, Hashable {
    case home, dorm, hotel, outdoors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dorm: return "Dorm"
        case .hotel: return "Hotel"
        case .outdoors: return "Outdoors"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .dorm: return "bed.double.fill"
        case .hotel: return "building.2.fill"
        case .outdoors: return "tree.fill"
        }
    }

    /// Quiet / small spaces: no jumping.
    var allowsJumping: Bool {
        switch self {
        case .dorm, .hotel: return false
        case .home, .outdoors: return true
        }
    }
}

/// Body areas a user can mark as uncomfortable.
enum BodyArea: String, Codable, CaseIterable, Identifiable, Hashable, Comparable {
    case neck, shoulders, wrists, lowerBack, hips, knees, ankles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        case .wrists: return "Wrists"
        case .lowerBack: return "Lower back"
        case .hips: return "Hips"
        case .knees: return "Knees"
        case .ankles: return "Ankles"
        }
    }

    var symbol: String {
        switch self {
        case .neck: return "person.crop.circle"
        case .shoulders: return "figure.arms.open"
        case .wrists: return "hand.raised.fill"
        case .lowerBack: return "figure.cooldown"
        case .hips: return "figure.walk"
        case .knees: return "figure.step.training"
        case .ankles: return "shoeprints.fill"
        }
    }

    private var order: Int { BodyArea.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: BodyArea, rhs: BodyArea) -> Bool { lhs.order < rhs.order }
}

/// The five movement families from the proposal, used for a balanced rotation.
enum MovementCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case push, squat, hinge, core, mobility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push: return "Push"
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .core: return "Core"
        case .mobility: return "Mobility"
        }
    }

    var subtitle: String {
        switch self {
        case .push: return "Chest, shoulders, arms"
        case .squat: return "Legs"
        case .hinge: return "Glutes, hamstrings, back"
        case .core: return "Abs & stability"
        case .mobility: return "Range of motion"
        }
    }

    var symbol: String {
        switch self {
        case .push: return "figure.strengthtraining.functional"
        case .squat: return "figure.cross.training"
        case .hinge: return "figure.core.training"
        case .core: return "figure.core.training"
        case .mobility: return "figure.flexibility"
        }
    }
}

/// Post-workout rating.
enum DifficultyRating: String, Codable, CaseIterable, Identifiable, Hashable {
    case tooEasy, aboutRight, tooHard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooEasy: return "Too easy"
        case .aboutRight: return "About right"
        case .tooHard: return "Too hard"
        }
    }

    var emoji: String {
        switch self {
        case .tooEasy: return "😴"
        case .aboutRight: return "👌"
        case .tooHard: return "🥵"
        }
    }

    /// How the next suggested difficulty moves.
    var adjustment: Int {
        switch self {
        case .tooEasy: return 1
        case .aboutRight: return 0
        case .tooHard: return -1
        }
    }
}

enum ActivityOrigin: String, Codable, Hashable {
    case inApp, external
}

/// Activity types for the shared log (in-app sessions and outside activities).
enum ActivityKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case emberWorkout, gym, run, walk, cycling, swim, tennis, badminton, basketball, football, yoga, dance, hiking, climbing, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emberWorkout: return "Ember workout"
        case .gym: return "Gym"
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycling: return "Cycling"
        case .swim: return "Swim"
        case .tennis: return "Tennis"
        case .badminton: return "Badminton"
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .yoga: return "Yoga"
        case .dance: return "Dance"
        case .hiking: return "Hiking"
        case .climbing: return "Climbing"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .emberWorkout: return "flame.fill"
        case .gym: return "dumbbell.fill"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swim: return "figure.pool.swim"
        case .tennis: return "figure.tennis"
        case .badminton: return "figure.badminton"
        case .basketball: return "figure.basketball"
        case .football: return "figure.soccer"
        case .yoga: return "figure.yoga"
        case .dance: return "figure.dance"
        case .hiking: return "figure.hiking"
        case .climbing: return "figure.climbing"
        case .other: return "sparkles"
        }
    }

    /// Kinds a user can pick when logging an outside activity.
    static var external: [ActivityKind] { allCases.filter { $0 != .emberWorkout } }
}
