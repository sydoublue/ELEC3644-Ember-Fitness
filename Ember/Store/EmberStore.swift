import Foundation
import Observation

struct AppSettings: Codable, Hashable {
    var hasOnboarded = false
    var name = ""
    var voiceCues = true
    var haptics = true
    var weeklyGoalMinutes = 90
    var youtubeAPIKey = ""
    var reminderEnabled = false
    var reminderHour = 18
    var reminderMinute = 0
}

/// Everything Ember keeps, stored on-device as one JSON file (proposal §2.6). No account, no server.
@Observable
final class EmberStore {

    private struct Snapshot: Codable {
        var settings = AppSettings()
        var lastSetup: SetupInput?
        var feedbacks: [Feedback] = []
        var sessions: [Session] = []
        var activities: [Activity] = []
        var scans: [BodyScanResult] = []
    }

    var settings = AppSettings() { didSet { save() } }
    private(set) var lastSetup: SetupInput?
    private(set) var feedbacks: [Feedback] = []
    private(set) var sessions: [Session] = []
    private(set) var activities: [Activity] = []
    private(set) var scans: [BodyScanResult] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isLoading = false

    init(fileName: String = "ember-data.json", inMemory: Bool = false) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = inMemory ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                           : dir.appendingPathComponent(fileName)
        load()
    }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        settings = snap.settings
        lastSetup = snap.lastSetup
        feedbacks = snap.feedbacks
        sessions = snap.sessions
        activities = snap.activities
        scans = snap.scans
    }

    private func save() {
        guard !isLoading else { return }
        let snap = Snapshot(settings: settings, lastSetup: lastSetup, feedbacks: feedbacks,
                            sessions: sessions, activities: activities, scans: scans)
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Ember: failed to save – \(error)")
        }
    }

    // MARK: Setup memory + feedback bias (§2.1, §2.4)

    var lastFeedback: Feedback? { feedbacks.max { $0.date < $1.date } }

    /// Pre-filled setup: last difficulty & duration, nudged by the last feedback; reported discomfort pre-selected.
    func suggestedSetup() -> SetupInput {
        var input = lastSetup ?? SetupInput()
        input.focus = []
        input.preferredExercises = []
        if let fb = lastFeedback {
            input.feeling = Feeling.from(difficulty: fb.suggestedNextDifficulty)
            input.discomfort = fb.discomfort
        }
        return input
    }

    func rememberSetup(_ input: SetupInput) {
        var stored = input
        stored.focus = []
        stored.preferredExercises = []
        lastSetup = stored
        save()
    }

    // MARK: Sessions & feedback

    func record(session: Session, plan: WorkoutPlan) {
        sessions.append(session)
        let minutes = max(1, Int((Double(session.elapsedSeconds) / 60).rounded()))
        let activity = Activity(date: session.startedAt,
                                title: "Ember · \(plan.input.feeling.title)",
                                minutes: minutes,
                                kind: .emberWorkout,
                                origin: .inApp,
                                notes: "\(session.completedCount) done · \(session.skippedCount) skipped",
                                sessionID: session.id,
                                effort: plan.input.difficulty)
        activities.append(activity)
        save()
    }

    func save(feedback: Feedback) {
        feedbacks.append(feedback)
        save()
    }

    // MARK: Activities (§2.5)

    func add(activity: Activity) {
        activities.append(activity)
        save()
    }

    func update(activity: Activity) {
        guard let i = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[i] = activity
        save()
    }

    func delete(activityID: UUID) {
        activities.removeAll { $0.id == activityID }
        save()
    }

    var activitiesNewestFirst: [Activity] { activities.sorted { $0.date > $1.date } }

    func session(id: UUID?) -> Session? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: Body scans

    func add(scan: BodyScanResult) {
        scans.append(scan)
        save()
    }

    var latestScan: BodyScanResult? { scans.max { $0.date < $1.date } }

    // MARK: Reset

    func resetAll() {
        let keepOnboarding = settings.hasOnboarded
        isLoading = true
        settings = AppSettings()
        settings.hasOnboarded = keepOnboarding
        isLoading = false
        lastSetup = nil
        feedbacks = []
        sessions = []
        activities = []
        scans = []
        save()
    }

    // MARK: Stats

    func minutes(from start: Date, to end: Date) -> Int {
        activities.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.minutes }
    }

    var minutesThisWeek: Int {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        return minutes(from: start, to: Date().addingTimeInterval(1))
    }

    /// Consecutive days (ending today or yesterday) with at least one activity.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(activities.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    /// Minutes per day for the last `count` days, oldest first.
    func dailyMinutes(lastDays count: Int) -> [DayMinutes] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [DayMinutes] = []
        for offset in (0..<count).reversed() {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today),
                  let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let inDay = activities.filter { $0.date >= day && $0.date < next }
            let inApp = inDay.filter { $0.origin == .inApp }.reduce(0) { $0 + $1.minutes }
            let ext = inDay.filter { $0.origin == .external }.reduce(0) { $0 + $1.minutes }
            result.append(DayMinutes(day: day, inApp: inApp, external: ext))
        }
        return result
    }
}

struct DayMinutes: Identifiable, Hashable {
    var day: Date
    var inApp: Int
    var external: Int
    var id: Date { day }
    var total: Int { inApp + external }
}
