import SwiftUI

struct VideoTabView: View {
    @Environment(VideoLounge.self) private var lounge
    @Binding var showRestSheet: Bool
    @State private var library = VideoLibrary.load()
    @State private var path = NavigationPath()
    @State private var section = VideoCategory.followAlong

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Video")
                        .font(.ember(34, .bold))
                        .foregroundStyle(Theme.ink)
                    Text("A fixed list for idle time at the gym. It is not part of Daily Pick, and nothing here is recommended.")
                        .font(.ember(15))
                        .foregroundStyle(Theme.inkSoft)

                    if let remaining = lounge.remaining {
                        RestBanner(remaining: remaining) { lounge.cancelRest() }
                    }

                    if let problem = library.problem {
                        Text(problem)
                            .font(.ember(15))
                            .foregroundStyle(Theme.ink)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .emberCard(padding: 14)
                    }

                    sectionSwitch
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                TabView(selection: $section) {
                    catalogPage(.followAlong)
                        .tag(VideoCategory.followAlong)
                    catalogPage(.lightShort)
                        .tag(VideoCategory.lightShort)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .emberBackground()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rest") { showRestSheet = true }
                        .font(.ember(16, .semibold))
                }
            }
            .navigationDestination(for: CatalogVideo.self) { video in
                YouTubePlayerScreen(video: video)
            }
        }
    }

    private var sectionSwitch: some View {
        HStack(spacing: 8) {
            ForEach(VideoCategory.allCases, id: \.self) { category in
                let selected = section == category
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = category }
                } label: {
                    Text(category.title)
                        .font(.ember(14, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? Color.white : Theme.ink)
                        .background(selected ? Theme.emberGradient : LinearGradient(colors: [Theme.surface, Theme.surface], startPoint: .top, endPoint: .bottom), in: Capsule())
                        .overlay(Capsule().stroke(selected ? Color.clear : Theme.line))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video sections")
    }

    private func catalogPage(_ category: VideoCategory) -> some View {
        let rows = library.items(in: category)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(category.detail)
                    .font(.ember(15))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if rows.isEmpty, library.problem == nil {
                    Text("Nothing in this section.")
                        .font(.ember(15))
                        .foregroundStyle(Theme.inkSoft)
                }
                ForEach(rows) { video in
                    Button {
                        path.append(video)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(video.title)
                                    .font(.ember(16, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Text(video.sourceCredit)
                                    .font(.ember(14))
                                    .foregroundStyle(Theme.inkSoft)
                                Text(Fmt.clock(video.durationSeconds))
                                    .font(.ember(14))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.ember)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).stroke(Theme.line))
                    }
                    .buttonStyle(.plain)
                }
                Text("Playback uses the official YouTube player. Videos are not downloaded, cached, or available offline. The list above still shows without a connection.")
                    .font(.ember(13))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

struct RestBanner: View {
    var remaining: Int
    var cancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REST")
                    .font(.ember(12, .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ember)
                Text(Fmt.clock(remaining))
                    .font(.ember(28, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button("Cancel", action: cancel)
                .font(.ember(16, .semibold))
                .foregroundStyle(Theme.ember)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).stroke(Theme.line))
        .accessibilityElement(children: .combine)
    }
}

struct RestDurationSheet: View {
    @Bindable var lounge: VideoLounge
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = RestReminderClock.defaultMinutes

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("How long is this rest?")
                    .font(.ember(22, .bold))
                    .foregroundStyle(Theme.ink)
                Text("The default is 3 minutes. When time is up, Ember pauses the video and tells you to start the next set. If you leave the app, a notification fires too.")
                    .font(.ember(16))
                    .foregroundStyle(Theme.inkSoft)
                if let remaining = lounge.remaining {
                    Text("A reminder is already running (\(Fmt.clock(remaining)) left). Starting a new one replaces it.")
                        .font(.ember(15))
                        .foregroundStyle(Theme.inkSoft)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.ember(17, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(minutes) min")
                        .font(.ember(28, .bold))
                        .foregroundStyle(Theme.ember)
                    Slider(
                        value: Binding(
                            get: { Double(minutes) },
                            set: { minutes = Int($0.rounded()) }
                        ),
                        in: Double(RestReminderClock.minimumMinutes)...Double(RestReminderClock.maximumMinutes),
                        step: 1
                    )
                    .tint(Theme.ember)
                }
                Button("Start reminder") {
                    lounge.startRest(minutes: minutes)
                    dismiss()
                }
                .buttonStyle(.emberPrimary)
                Button("Not now") { dismiss() }
                    .buttonStyle(.emberSecondary)
                Spacer()
            }
            .padding(24)
            .emberBackground()
            .navigationTitle("Rest reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            minutes = lounge.restMinutes
            Task { await RestNotificationAccess.requestIfNeeded() }
        }
    }
}
