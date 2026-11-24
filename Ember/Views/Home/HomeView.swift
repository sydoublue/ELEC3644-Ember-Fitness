import SwiftUI

struct HomeView: View {
    @Environment(EmberStore.self) private var store
    @Environment(AppRouter.self) private var router

    private let generator = WorkoutGenerator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                heroCard
                weekCard
                dailyPick
                scanCard
                recentCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .emberBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let name = store.settings.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.ember(12, .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .tracking(1.2)
                Text(greeting)
                    .font(.ember(28, .bold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { router.showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.line))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }

    // MARK: Hero

    private var suggested: SetupInput { store.suggestedSetup() }

    private var feedbackLine: String? {
        guard let fb = store.lastFeedback else { return nil }
        switch fb.rating {
        case .tooHard: return "Last session felt too hard, so today starts a notch easier."
        case .tooEasy: return "Last session felt too easy, so today starts a notch harder."
        case .aboutRight: return "Last session felt about right. Same level today."
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                Text("SHORT ON TIME?")
                    .tracking(1.2)
            }
            .font(.ember(13, .bold))
            .foregroundStyle(.white.opacity(0.85))

            Text("A quick workout,\nshaped to how you feel.")
                .font(.ember(26, .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let feedbackLine {
                Text(feedbackLine)
                    .font(.ember(14))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 10) {
                Button { router.openSetup() } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.ember(17, .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(Theme.emberDeep)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button {
                    let plan = generator.generate(suggested)
                    store.rememberSetup(plan.input)
                    router.openPlan(plan)
                } label: {
                    VStack(spacing: 1) {
                        Text("Quick start").font(.ember(14, .bold))
                        Text("\(suggested.duration) min · \(suggested.feeling.title)").font(.ember(12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Skips setup and uses your last settings")
            }
        }
        .padding(20)
        .background {
            ZStack(alignment: .bottomTrailing) {
                Theme.emberGradient
                ExerciseFigureView(motion: .jumpingJack, tint: .white.opacity(0.18), showsGround: false, speed: 0.6)
                    .frame(width: 170)
                    .offset(x: 30, y: 30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.ember.opacity(0.3), radius: 20, y: 10)
    }

    // MARK: Week

    private var weekCard: some View {
        let goal = max(1, store.settings.weeklyGoalMinutes)
        let minutes = store.minutesThisWeek
        let progress = Double(minutes) / Double(goal)
        return HStack(spacing: 18) {
            ZStack {
                RingProgress(progress: progress, lineWidth: 11)
                VStack(spacing: 0) {
                    Text("\(minutes)").font(.ember(24, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    Text("of \(goal) min").font(.ember(11)).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 10) {
                Text("This week").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
                HStack(spacing: 14) {
                    metric(value: "\(store.streakDays)", label: "day streak", symbol: "flame.fill", tint: Theme.ember)
                    metric(value: "\(weekSessions)", label: "sessions", symbol: "bolt.fill", tint: Theme.amber)
                }
                Text(progress >= 1 ? "Goal reached. Nice!" : "\(max(0, goal - minutes)) min to your goal")
                    .font(.ember(13))
                    .foregroundStyle(progress >= 1 ? Theme.good : Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .emberCard()
    }

    private var weekSessions: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return store.activities.filter { $0.date >= start }.count
    }

    private func metric(value: String, label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 13, weight: .bold))
            Text(value).font(.ember(16, .bold)).foregroundStyle(Theme.ink)
            Text(label).font(.ember(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: Daily pick

    private var pick: Exercise {
        let regular = ExerciseLibrary.all.filter { !$0.isRecovery }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return regular[day % regular.count]
    }

    private var dailyPick: some View {
        Button { router.homePath.append(.exercise(pick.id)) } label: {
            HStack(spacing: 16) {
                ExerciseFigureView(motion: pick.motion, tint: Theme.color(for: pick.category))
                    .frame(width: 96, height: 96)
                    .background(Theme.color(for: pick.category).opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAILY PICK").font(.ember(12, .bold)).tracking(1.1).foregroundStyle(Theme.color(for: pick.category))
                    Text(pick.name).font(.ember(19, .bold)).foregroundStyle(Theme.ink)
                    Text(pick.instruction).font(.ember(13)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    LevelDots(level: pick.level, tint: Theme.color(for: pick.category))
                }
                Spacer(minLength: 0)
            }
            .emberCard(padding: 14)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Scan

    private var scanCard: some View {
        Button {
            if let scan = store.latestScan {
                var input = suggested
                input.focus = scan.focusCategories
                input.preferredExercises = scan.recommendedExerciseIDs
                router.openSetup(prefill: input)
            } else {
                router.tab = .scan
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.calm.opacity(0.12))
                    Image(systemName: "figure.stand").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.calm)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    if let scan = store.latestScan {
                        Text("Body scan · \(scan.score)/100").font(.ember(16, .bold)).foregroundStyle(Theme.ink)
                        Text(scan.findings.first.map { "Focus: \($0.title.lowercased()). Build a workout for it." }
                             ?? "Looking balanced. Build a workout from your scan.")
                            .font(.ember(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                    } else {
                        Text("Try the AI Body Scan").font(.ember(16, .bold)).foregroundStyle(Theme.ink)
                        Text("Your camera checks posture & movement, then picks exercises for you.")
                            .font(.ember(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }
            .emberCard(padding: 14)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Recent

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent", trailing: AnyView(
                Button("See all") { router.tab = .activity }
                    .font(.ember(15, .semibold))
            ))
            let recent = Array(store.activitiesNewestFirst.prefix(3))
            if recent.isEmpty {
                Text("Your workouts and outside activities will show up here.")
                    .font(.ember(14))
                    .foregroundStyle(Theme.inkSoft)
                    .emberCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { activity in
                        ActivityRow(activity: activity)
                        if activity.id != recent.last?.id { Divider().overlay(Theme.line) }
                    }
                }
                .emberCard(padding: 6)
            }
        }
    }
}
