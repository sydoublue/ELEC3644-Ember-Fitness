import SwiftUI

/// How-to for one exercise: animated figure, steps, cues, and YouTube demos.
struct ExerciseDetailView: View {
    let exerciseID: String

    var body: some View {
        if let ex = ExerciseLibrary.exercise(exerciseID) {
            content(ex)
        } else {
            ContentUnavailableView("Exercise not found", systemImage: "questionmark")
        }
    }

    private func content(_ ex: Exercise) -> some View {
        let tint = Theme.color(for: ex.category)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExerciseFigureView(motion: ex.motion, tint: tint, animated: true)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .background(
                        LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(ex.isRecovery ? "Recovery" : ex.category.title)
                            .font(.ember(13, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(ex.isRecovery ? Theme.good : tint, in: Capsule())
                        LevelDots(level: ex.level, tint: tint)
                        if ex.isJumping {
                            Label("Jumping", systemImage: "arrow.up.and.down").font(.ember(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Text(ex.name).font(.ember(30, .bold)).foregroundStyle(Theme.ink)
                    Text(ex.instruction).font(.ember(16)).foregroundStyle(Theme.inkSoft)
                }

                FlowLayout(spacing: 6) {
                    ForEach(ex.muscles, id: \.self) { m in
                        Text(m).font(.ember(13, .medium)).foregroundStyle(tint)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("How to").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
                    ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.ember(13, .bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(tint, in: Circle())
                            Text(step).font(.ember(15)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .emberCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Form cues").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
                    ForEach(ex.cues, id: \.self) { cue in
                        Label(cue, systemImage: "checkmark.seal.fill")
                            .font(.ember(15)).foregroundStyle(Theme.ink)
                            .symbolRenderingMode(.multicolor)
                    }
                    if !ex.stresses.isEmpty {
                        Text("Skipped automatically if you report " +
                             ex.stresses.sorted().map { $0.title.lowercased() }.joined(separator: ", ") + " discomfort.")
                            .font(.ember(13)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                    }
                }
                .emberCard()

                VideoDemosSection(exercise: ex)
                    .emberCard()

                Text("Ember gives general fitness guidance, not medical advice. Stop if something hurts.")
                    .font(.ember(12)).foregroundStyle(Theme.inkSoft)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .emberBackground()
        .navigationTitle(ex.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
