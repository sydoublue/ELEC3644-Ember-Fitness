import SwiftUI

/// Quick feedback (proposal §2.4). The rating nudges the next suggested difficulty;
/// marked areas are pre-selected under "More" next time.
struct FeedbackView: View {
    let session: Session
    let plan: WorkoutPlan
    var onDone: (Feedback?) -> Void

    @State private var rating: DifficultyRating?
    @State private var discomfort: Set<BodyArea> = []
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                celebration
                stats
                ratingSection
                discomfortSection
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .emberBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    guard let rating else { return }
                    onDone(Feedback(sessionID: session.id, date: Date(), rating: rating,
                                    discomfort: discomfort, difficultyUsed: plan.input.difficulty))
                } label: { Text("Done") }
                .buttonStyle(.emberPrimary)
                .disabled(rating == nil)
                .opacity(rating == nil ? 0.5 : 1)
                Button("Skip feedback") { onDone(nil) }
                    .buttonStyle(.emberGhost)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .background(.ultraThinMaterial)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) { appeared = true } }
        .sensoryFeedback(.success, trigger: appeared)
    }

    private var celebration: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.emberGradient).frame(width: 110, height: 110)
                    .shadow(color: Theme.ember.opacity(0.4), radius: 24, y: 10)
                Image(systemName: "flame.fill").font(.system(size: 50)).foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            Text(session.skippedCount == 0 ? "Workout complete!" : "Nice effort!")
                .font(.ember(30, .bold)).foregroundStyle(Theme.ink)
            Text("Saved to your activity log.").font(.ember(14)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.top, 30)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(value: Fmt.clock(session.elapsedSeconds), label: "total time", symbol: "clock.fill")
            StatTile(value: "\(session.completedCount)", label: "done", symbol: "checkmark", tint: Theme.good)
            StatTile(value: "\(session.skippedCount)", label: "skipped", symbol: "forward.fill", tint: Theme.inkSoft)
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How was that?").font(.ember(22, .bold)).foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                ForEach(DifficultyRating.allCases) { r in
                    let selected = rating == r
                    Button { withAnimation(.spring(response: 0.3)) { rating = r } } label: {
                        VStack(spacing: 8) {
                            Text(r.emoji).font(.system(size: 34))
                            Text(r.title).font(.ember(14, .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(selected ? Color.white : Theme.ink)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selected ? AnyShapeStyle(Theme.emberGradient) : AnyShapeStyle(Theme.surface))
                        }
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Color.clear : Theme.line))
                        .scaleEffect(selected ? 1.03 : 1)
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
            if let rating {
                Text(nextHint(rating)).font(.ember(13)).foregroundStyle(Theme.inkSoft)
                    .transition(.opacity)
            }
        }
    }

    private func nextHint(_ r: DifficultyRating) -> String {
        let next = Feeling.from(difficulty: min(5, max(1, plan.input.difficulty + r.adjustment)))
        switch r {
        case .tooEasy: return "Next time Ember will suggest \"\(next.title)\", one level up."
        case .tooHard: return "Next time Ember will suggest \"\(next.title)\", one level down."
        case .aboutRight: return "Ember will keep the same level next time."
        }
    }

    private var discomfortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anything feel uncomfortable?").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            Text("Optional. These will be pre-selected next time so Ember avoids them.")
                .font(.ember(13)).foregroundStyle(Theme.inkSoft)
            FlowLayout {
                ForEach(BodyArea.allCases) { area in
                    Chip(title: area.title, isOn: discomfort.contains(area), tint: Theme.warn) {
                        if discomfort.contains(area) { discomfort.remove(area) } else { discomfort.insert(area) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
