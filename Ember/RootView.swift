import SwiftUI

enum AppTab: Hashable {
    case dailyPick
    case video
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.dailyPick
    @State private var showRestSheet = false
    @State private var lounge = VideoLounge()

    var body: some View {
        @Bindable var lounge = self.lounge
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Daily Pick", systemImage: "flame.fill") }
                .tag(AppTab.dailyPick)
            VideoTabView(showRestSheet: $showRestSheet)
                .tabItem { Label("Video", systemImage: "play.rectangle.fill") }
                .tag(AppTab.video)
        }
        .environment(lounge)
        .onChange(of: tab) { _, newTab in
            if newTab == .video {
                showRestSheet = true
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            lounge.tick(now: date)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                lounge.tick()
            }
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
    }
}
