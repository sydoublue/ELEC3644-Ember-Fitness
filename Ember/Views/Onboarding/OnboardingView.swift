import SwiftUI

struct OnboardingView: View {
    @Environment(EmberStore.self) private var store
    @State private var page = 0
    @State private var name = ""
    @State private var goal = 90

    private struct Page {
        let motion: MotionKind
        let title: String
        let body: String
    }

    private let pages = [
        Page(motion: .jumpingJack, title: "Exercise, even when\nyou're short on time",
             body: "Pick how you feel and how long you have. Ember builds a short bodyweight workout in seconds, for your dorm, hotel or living room."),
        Page(motion: .squat, title: "It learns from\nhow it felt",
             body: "Rate each session. Too hard? Next time eases off. Sore knees? Ember avoids them and adds a gentle stretch."),
        Page(motion: .wallAngel, title: "AI that stays\non your phone",
             body: "Body Scan uses your camera to check posture and movement, then picks exercises for you. Nothing is uploaded, and there's no account."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    pageView(p).tag(i)
                }
                setupPage.tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            HStack(spacing: 6) {
                ForEach(0...pages.count, id: \.self) { i in
                    Capsule().fill(i == page ? Theme.ember : Theme.line)
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.3), value: page)
            .padding(.bottom, 18)

            Button {
                if page < pages.count {
                    page += 1
                } else {
                    store.settings.name = name.trimmingCharacters(in: .whitespaces)
                    store.settings.weeklyGoalMinutes = goal
                    store.settings.hasOnboarded = true
                }
            } label: {
                Text(page < pages.count ? "Continue" : "Let's go")
            }
            .buttonStyle(.emberPrimary)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .emberBackground()
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ExerciseFigureView(motion: p.motion, tint: Theme.ember)
                .frame(width: 240, height: 240)
                .background(Circle().fill(Theme.glow).frame(width: 280, height: 280))
            VStack(spacing: 12) {
                Text(p.title).font(.ember(30, .bold)).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
                Text(p.body).font(.ember(17)).multilineTextAlignment(.center).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 8)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "flame.fill").font(.system(size: 44)).foregroundStyle(Theme.emberGradient)
            Text("Let's set you up").font(.ember(32, .bold)).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?").font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                TextField("Name (optional)", text: $name)
                    .font(.ember(18))
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                    .submitLabel(.done)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Weekly movement goal").font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(goal) min").font(.ember(20, .bold)).foregroundStyle(Theme.ember)
                }
                Slider(value: Binding(get: { Double(goal) }, set: { goal = Int($0) }), in: 30...300, step: 15)
                Text("The WHO suggests 150 minutes of moderate activity a week. Any amount counts.")
                    .font(.ember(13)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
