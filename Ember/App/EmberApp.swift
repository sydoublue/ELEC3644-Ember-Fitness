import SwiftUI

@main
struct EmberApp: App {
    @State private var store = EmberStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .tint(Theme.ember)
        }
    }
}

enum AppTab: Hashable {
    case today, scan, coach, video, activity
}

enum HomeRoute: Hashable {
    case setup
    case plan(WorkoutPlan)
    case exercise(String)
}

struct ActiveWorkout: Identifiable {
    let id = UUID()
    let plan: WorkoutPlan
}

/// App-wide navigation so any tab (Coach, Body Scan) can open setup or start a workout.
@Observable
final class AppRouter {
    var tab: AppTab = .today
    var homePath: [HomeRoute] = []
    var activeWorkout: ActiveWorkout?
    var showSettings = false
    /// Extra setup context handed to the Setup screen (e.g. focus from a body scan).
    var setupPrefill: SetupInput?

    func openSetup(prefill: SetupInput? = nil) {
        setupPrefill = prefill
        tab = .today
        homePath = [.setup]
    }

    func openPlan(_ plan: WorkoutPlan) {
        tab = .today
        homePath = [.plan(plan)]
    }

    func start(_ plan: WorkoutPlan) {
        activeWorkout = ActiveWorkout(plan: plan)
    }

    func finishWorkout() {
        activeWorkout = nil
        homePath = []
    }
}

struct RootView: View {
    @Environment(EmberStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var lounge = VideoLounge()
    @State private var showRestSheet = false

    var body: some View {
        @Bindable var router = router
        @Bindable var lounge = lounge
        Group {
            if store.settings.hasOnboarded {
                TabView(selection: $router.tab) {
                    NavigationStack(path: $router.homePath) {
                        HomeView()
                            .navigationDestination(for: HomeRoute.self) { route in
                                switch route {
                                case .setup: SetupView()
                                case .plan(let plan): PlanView(plan: plan)
                                case .exercise(let id): ExerciseDetailView(exerciseID: id)
                                }
                            }
                    }
                    .tabItem { Label("Today", systemImage: "flame.fill") }
                    .tag(AppTab.today)

                    BodyScanHomeView()
                        .tabItem { Label("Body Scan", systemImage: "figure.stand") }
                        .tag(AppTab.scan)

                    CoachView()
                        .tabItem { Label("Coach", systemImage: "sparkles") }
                        .tag(AppTab.coach)

                    VideoTabView(showRestSheet: $showRestSheet)
                        .tabItem { Label("Video", systemImage: "play.rectangle.fill") }
                        .tag(AppTab.video)

                    LogView()
                        .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.portrait") }
                        .tag(AppTab.activity)
                }
                .environment(lounge)
                .onChange(of: router.tab) { _, newTab in
                    if newTab == .video {
                        showRestSheet = true
                    }
                }
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                    lounge.tick(now: date)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { lounge.tick() }
                }
                .onChange(of: lounge.showRestAlert) { _, show in
                    if show { showRestSheet = false }
                }
                .sheet(isPresented: $showRestSheet) {
                    RestDurationSheet(lounge: lounge)
                }
                .alert("Rest is over", isPresented: $lounge.showRestAlert) {
                    Button("Next set") {}
                } message: {
                    Text("Time to start your next set. Playback is paused.")
                }
                .fullScreenCover(item: $router.activeWorkout) { workout in
                    WorkoutFlowView(plan: workout.plan)
                }
                .sheet(isPresented: $router.showSettings) {
                    SettingsView()
                }
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.settings.hasOnboarded)
    }
}
