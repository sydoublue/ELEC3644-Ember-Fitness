import Foundation
import Observation

/// Plays a `WorkoutPlan` one exercise at a time with work / rest timers (proposal §2.3).
/// Strength moves can be completed by repetitions instead of the work timer.
/// Records completed and skipped items plus rest adjustments into a `Session`.
@Observable
final class SessionPlayer {

    enum Phase: Equatable {
        case getReady, work, rest, finished
    }

    enum Event {
        case phaseChanged(Phase)
        case countdown(Int)
        case halfway
        case finished
    }

    static let getReadySeconds: Double = 5
    static let extraRestSeconds: Double = 15

    let plan: WorkoutPlan
    let startedAt = Date()

    private(set) var index = 0
    private(set) var phase: Phase = .getReady
    private(set) var remaining: Double = SessionPlayer.getReadySeconds
    private(set) var phaseDuration: Double = SessionPlayer.getReadySeconds
    private(set) var isPaused = false
    /// "Need more rest" can be used once per break.
    private(set) var extraRestUsed = false
    private(set) var results: [SessionItemResult] = []
    private(set) var skippedBreaks = 0
    private(set) var extendedBreaks = 0
    private(set) var endedAt: Date?
    private(set) var loggedReps = 0

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var phaseEnd = Date()
    @ObservationIgnored private var lastCountdown = Int.max
    @ObservationIgnored private var announcedHalfway = false
    @ObservationIgnored private var workStartedAt: Date?

    init(plan: WorkoutPlan) {
        self.plan = plan
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Derived state

    var current: PlanItem? { plan.items.indices.contains(index) ? plan.items[index] : nil }

    /// During work: the item after this one. During rest: the item coming up.
    var upNext: PlanItem? {
        let i = index + 1
        return plan.items.indices.contains(i) ? plan.items[i] : nil
    }

    var isRepWork: Bool { phase == .work && (current?.targetReps ?? 0) > 0 }
    var targetReps: Int { current?.targetReps ?? 0 }

    var phaseProgress: Double {
        if isRepWork {
            guard targetReps > 0 else { return 0 }
            return min(1, max(0, Double(loggedReps) / Double(targetReps)))
        }
        guard phaseDuration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining / phaseDuration))
    }

    /// Overall progress through the plan, 0...1.
    var overallProgress: Double {
        guard !plan.items.isEmpty else { return 1 }
        if phase == .finished { return 1 }
        let done = Double(index) + (phase == .rest ? 1 : (phase == .work ? phaseProgress : 0))
        return min(1, done / Double(plan.items.count))
    }

    var remainingWholeSeconds: Int { max(0, Int(remaining.rounded(.up))) }

    // MARK: Controls

    func start() {
        guard timer == nil, phase != .finished else { return }
        begin(.getReady, duration: Self.getReadySeconds)
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func togglePause() {
        guard phase != .finished else { return }
        if isPaused {
            phaseEnd = Date().addingTimeInterval(remaining)
            isPaused = false
        } else {
            if !isRepWork {
                remaining = max(0, phaseEnd.timeIntervalSinceNow)
            }
            isPaused = true
        }
    }

    /// Skip the current exercise (recorded as skipped).
    func skipExercise() {
        switch phase {
        case .getReady:
            begin(.work, duration: Double(current?.workSeconds ?? 0))
        case .work:
            recordCurrent(status: .skipped)
            afterWork()
        case .rest, .finished:
            break
        }
    }

    /// Log one repetition during a count-based set.
    func logRep() {
        guard phase == .work, let target = current?.targetReps, target > 0 else { return }
        loggedReps = min(target, loggedReps + 1)
        if loggedReps >= target {
            completeCurrentExercise()
        }
    }

    /// Finish the current work interval, including a rep set early.
    func completeCurrentExercise() {
        guard phase == .work else { return }
        recordCurrent(status: .completed)
        afterWork()
    }

    /// "I'm good, skip the break."
    func skipBreak() {
        guard phase == .rest else { return }
        skippedBreaks += 1
        moveToNext()
    }

    /// "Need more rest": +15s, once per break.
    func addRest() {
        guard phase == .rest, !extraRestUsed else { return }
        extraRestUsed = true
        extendedBreaks += 1
        phaseDuration += Self.extraRestSeconds
        if isPaused {
            remaining += Self.extraRestSeconds
        } else {
            phaseEnd = phaseEnd.addingTimeInterval(Self.extraRestSeconds)
            remaining = max(0, phaseEnd.timeIntervalSinceNow)
        }
    }

    /// End the workout now; anything not done is recorded as skipped.
    func endEarly() {
        guard phase != .finished else { return }
        if phase == .work { recordCurrent(status: .skipped) }
        let recordedIDs = results.count
        if recordedIDs < plan.items.count {
            for item in plan.items[recordedIDs...] {
                results.append(SessionItemResult(exerciseID: item.exerciseID, status: .skipped,
                                                 activeSeconds: 0, isRecovery: item.isRecovery))
            }
        }
        finish()
    }

    func makeSession() -> Session {
        Session(startedAt: startedAt, endedAt: endedAt ?? Date(), input: plan.input,
                results: results, skippedBreaks: skippedBreaks, extendedBreaks: extendedBreaks)
    }

    // MARK: Engine

    func tick() {
        guard !isPaused, phase != .finished else { return }
        if isRepWork { return }
        remaining = max(0, phaseEnd.timeIntervalSinceNow)

        let whole = Int(remaining.rounded(.up))
        if whole <= 3, whole >= 1, whole < lastCountdown {
            lastCountdown = whole
            onEvent?(.countdown(whole))
        }
        if phase == .work, !announcedHalfway, phaseDuration >= 30, remaining <= phaseDuration / 2 {
            announcedHalfway = true
            onEvent?(.halfway)
        }
        if remaining <= 0 { advance() }
    }

    private func advance() {
        switch phase {
        case .getReady:
            begin(.work, duration: Double(current?.workSeconds ?? 0))
        case .work:
            recordCurrent(status: .completed)
            afterWork()
        case .rest:
            moveToNext()
        case .finished:
            break
        }
    }

    private func afterWork() {
        if let item = current, item.restSeconds > 0, upNext != nil {
            extraRestUsed = false
            begin(.rest, duration: Double(item.restSeconds))
        } else {
            moveToNext()
        }
    }

    private func moveToNext() {
        index += 1
        if index >= plan.items.count {
            finish()
        } else {
            begin(.work, duration: Double(current?.workSeconds ?? 0))
        }
    }

    private func begin(_ newPhase: Phase, duration: Double) {
        phase = newPhase
        phaseDuration = duration
        remaining = duration
        phaseEnd = Date().addingTimeInterval(max(0, duration))
        lastCountdown = Int.max
        announcedHalfway = false
        loggedReps = 0
        workStartedAt = newPhase == .work ? Date() : nil
        if isPaused { isPaused = false }
        onEvent?(.phaseChanged(newPhase))
    }

    private func recordCurrent(status: ItemStatus) {
        guard let item = current, results.count == index else { return }
        let elapsed: Int
        if let start = workStartedAt {
            elapsed = max(0, Int(Date().timeIntervalSince(start).rounded()))
        } else if status == .completed {
            elapsed = item.workSeconds
        } else {
            elapsed = Int(max(0, phaseDuration - remaining))
        }
        let reps = item.isRepWork ? (status == .completed ? (loggedReps > 0 ? loggedReps : item.targetReps) : loggedReps) : nil
        results.append(SessionItemResult(exerciseID: item.exerciseID, status: status,
                                         activeSeconds: elapsed, isRecovery: item.isRecovery,
                                         completedReps: reps))
    }

    private func finish() {
        phase = .finished
        remaining = 0
        endedAt = Date()
        timer?.invalidate()
        timer = nil
        onEvent?(.finished)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
