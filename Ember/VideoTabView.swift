import SwiftUI

struct VideoTabView: View {
    @Environment(VideoLounge.self) private var lounge
    @Binding var showRestSheet: Bool
    @State private var library = VideoLibrary.load()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("VIDEO")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(EmberColor.accent)
                    Text("Gym rest")
                        .font(.largeTitle.bold())
                        .foregroundStyle(EmberColor.ink)
                    Text("A fixed list for idle time at the gym. It is not part of Daily Pick, and nothing here is recommended.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if let remaining = lounge.remaining {
                        RestBanner(remaining: remaining) { lounge.cancelRest() }
                    }

                    if let problem = library.problem {
                        Text(problem)
                            .font(.body)
                            .foregroundStyle(EmberColor.ink)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }

                    catalogSection(.followAlong)
                    catalogSection(.lightShort)

                    Text("Playback uses the official YouTube player. Videos are not downloaded, cached, or available offline. The list above still shows without a connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(EmberColor.paper)
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rest") { showRestSheet = true }
                }
            }
            .navigationDestination(for: CatalogVideo.self) { video in
                YouTubePlayerScreen(video: video)
            }
        }
    }

    @ViewBuilder
    private func catalogSection(_ category: VideoCategory) -> some View {
        let rows = library.items(in: category)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(category.title)
                    .font(.title2.bold())
                    .foregroundStyle(EmberColor.ink)
                Text(category.detail)
                    .font(.title3)
                    .foregroundStyle(EmberColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rows.isEmpty, library.problem == nil {
                Text("Nothing in this section.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { video in
                Button {
                    path.append(video)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.title)
                                .font(.headline)
                                .foregroundStyle(EmberColor.ink)
                                .multilineTextAlignment(.leading)
                            Text(video.sourceCredit)
                                .font(.body)
                                .foregroundStyle(EmberColor.ink)
                            Text("\(clock(video.durationSeconds)) · \(video.category.rowNote)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(EmberColor.accent)
                            .accessibilityHidden(true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RestBanner: View {
    var remaining: Int
    var cancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REST")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(EmberColor.accent)
                Text(clock(remaining))
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(EmberColor.ink)
            }
            Spacer()
            Button("Cancel", action: cancel)
                .font(.headline)
                .foregroundStyle(EmberColor.accent)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
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
                    .font(.title2.bold())
                    .foregroundStyle(EmberColor.ink)
                Text("The default is 3 minutes. When time is up, Ember pauses the video and tells you to start the next set. If you leave the app, a notification fires too.")
                    .foregroundStyle(.secondary)
                if let remaining = lounge.remaining {
                    Text("A reminder is already running (\(clock(remaining)) left). Starting a new one replaces it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.headline)
                    Text("\(minutes) min")
                        .font(.title.bold())
                        .foregroundStyle(EmberColor.accent)
                    Slider(
                        value: Binding(
                            get: { Double(minutes) },
                            set: { minutes = Int($0.rounded()) }
                        ),
                        in: Double(RestReminderClock.minimumMinutes)...Double(RestReminderClock.maximumMinutes),
                        step: 1
                    )
                    .tint(EmberColor.accent)
                }
                Button("Start reminder") {
                    lounge.startRest(minutes: minutes)
                    dismiss()
                }
                .buttonStyle(EmberPrimaryButton())
                Button("Not now") { dismiss() }
                    .buttonStyle(EmberSecondaryButton())
                Spacer()
            }
            .padding(24)
            .background(EmberColor.paper)
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
