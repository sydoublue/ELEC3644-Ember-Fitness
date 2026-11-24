import SwiftUI

/// Plan preview (proposal §2.2 / §3): review moves, see why they were chosen, swap any, then start.
struct PlanView: View {
    @Environment(AppRouter.self) private var router
    @State var plan: WorkoutPlan
    @State private var showWhy = false
    @State private var replacing: PlanItem?
    @State private var detail: Exercise?

    private let generator = WorkoutGenerator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                ForEach(plan.notices, id: \.self) { notice in
                    InfoBanner(text: notice, symbol: "exclamationmark.triangle.fill", tint: Theme.warn)
                }
                whyCard
                itemsList
            }
            .padding(20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .emberBackground()
        .navigationTitle("Your plan")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { startBar }
        .sheet(item: $replacing) { item in
            ReplaceSheet(item: item, alternatives: generator.alternatives(for: item, in: plan)) { choice in
                withAnimation { plan = generator.replacing(item, with: choice, in: plan) }
            }
        }
        .sheet(item: $detail) { exercise in
            NavigationStack {
                ExerciseDetailView(exerciseID: exercise.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(plan.title.capitalizedFirst).font(.ember(26, .bold)).foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                pill(Fmt.clock(plan.totalSeconds), "clock.fill")
                pill("\(plan.mainItems.count) moves", "square.stack.3d.up.fill")
                pill("\(plan.workSecondsPerItem)s / \(plan.restSecondsPerItem)s", "timer")
            }
            // Category ribbon
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(plan.items) { item in
                        Capsule()
                            .fill(item.isRecovery ? Theme.good : Theme.color(for: item.exercise.category))
                            .frame(width: max(4, (geo.size.width - CGFloat(plan.items.count - 1) * 3) / CGFloat(max(1, plan.items.count))))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                ForEach(MovementCategory.allCases) { cat in
                    let count = plan.mainItems.filter { $0.exercise.category == cat }.count
                    if count > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.color(for: cat)).frame(width: 8, height: 8)
                            Text("\(cat.title) \(count)").font(.ember(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
        .emberCard()
    }

    private func pill(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.ember(13, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surfaceMuted, in: Capsule())
    }

    // MARK: Why

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showWhy.toggle() }
            } label: {
                HStack {
                    Label("How Ember built this", systemImage: "wand.and.stars")
                        .font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showWhy ? 180 : 0))
                        .foregroundStyle(Theme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showWhy {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.explanation.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.ember(12, .bold)).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Theme.ember, in: Circle())
                            Text(line).font(.ember(14)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !plan.excluded.isEmpty {
                        Text("Left out today").font(.ember(14, .semibold)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                        FlowLayout(spacing: 6) {
                            ForEach(plan.excluded, id: \.self) { ex in
                                Text("\(ex.name) · \(ex.reason)")
                                    .font(.ember(12))
                                    .foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.surfaceMuted, in: Capsule())
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .emberCard()
    }

    // MARK: Items

    private var itemsList: some View {
        VStack(spacing: 10) {
            ForEach(plan.items) { item in
                PlanItemRow(item: item, index: item.id + 1) {
                    detail = item.exercise
                } onReplace: {
                    replacing = item
                }
            }
            Text("Tip: tap a move for a demo, or swap it.")
                .font(.ember(12))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var startBar: some View {
        Button {
            router.start(plan)
        } label: {
            Label("Start workout", systemImage: "play.fill")
        }
        .buttonStyle(.emberPrimary)
        .disabled(plan.items.isEmpty)
        .opacity(plan.items.isEmpty ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

struct PlanItemRow: View {
    let item: PlanItem
    let index: Int
    var onTap: () -> Void
    var onReplace: () -> Void

    var body: some View {
        let ex = item.exercise
        HStack(spacing: 14) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    ExerciseThumb(exercise: ex, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(index)").font(.ember(12, .bold)).foregroundStyle(Theme.inkSoft)
                            Text(ex.name).font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                            if item.isRecovery {
                                Text("Optional").font(.ember(11, .bold)).foregroundStyle(Theme.good)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.good.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(item.reason ?? ex.category.title)
                            .font(.ember(13)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        Text(item.isRecovery ? "\(item.workSeconds)s" : "\(item.workSeconds)s work · \(item.restSeconds)s rest")
                            .font(.ember(12, .medium)).foregroundStyle(Theme.color(for: ex.category))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            Button(action: onReplace) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 38, height: 38)
                    .background(Theme.surfaceMuted, in: Circle())
            }
            .accessibilityLabel("Replace \(ex.name)")
        }
        .emberCard(padding: 12)
    }
}

/// Replace a move with another from the same category (respects location & discomfort).
struct ReplaceSheet: View {
    let item: PlanItem
    let alternatives: [Exercise]
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Same type as \(item.exercise.name), and still fits your place and discomfort.")
                        .font(.ember(14)).foregroundStyle(Theme.inkSoft)
                    if alternatives.isEmpty {
                        InfoBanner(text: "No other moves fit right now. Try changing location or discomfort in setup.")
                    }
                    ForEach(alternatives) { ex in
                        Button {
                            onPick(ex)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ExerciseThumb(exercise: ex, size: 54, animated: true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ex.name).font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                                    LevelDots(level: ex.level, tint: Theme.color(for: ex.category))
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.ember).font(.system(size: 22))
                            }
                            .emberCard(padding: 12)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(20)
            }
            .emberBackground()
            .navigationTitle("Replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
