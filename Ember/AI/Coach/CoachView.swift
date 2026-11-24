import SwiftUI

struct CoachView: View {
    @Environment(EmberStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var agent = CoachAgent()
    @State private var draft = ""
    @State private var path: [CoachRoute] = []
    @FocusState private var inputFocused: Bool

    enum CoachRoute: Hashable {
        case plan(WorkoutPlan)
        case exercise(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            aiBadge
                            ForEach(agent.messages) { msg in
                                MessageBubble(message: msg) { plan in
                                    path.append(.plan(plan))
                                } onStart: { plan in
                                    router.start(plan)
                                } onExercise: { id in
                                    path.append(.exercise(id))
                                }
                                .id(msg.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            if agent.isThinking {
                                TypingIndicator().id("typing")
                            }
                            if agent.messages.count <= 1 { suggestionChips }
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: agent.messages.count) {
                        if let id = agent.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                    .onChange(of: agent.isThinking) {
                        if agent.isThinking { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                    }
                }
                inputBar
            }
            .emberBackground()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { agent.reset() } } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("New conversation")
                        .disabled(agent.messages.count <= 1)
                }
            }
            .navigationDestination(for: CoachRoute.self) { route in
                switch route {
                case .plan(let plan): PlanView(plan: plan)
                case .exercise(let id): ExerciseDetailView(exerciseID: id)
                }
            }
        }
    }

    private var aiBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Theme.ember)
            Text(LocalAI.isAvailable ? "Powered by Apple Intelligence, on-device" : "On-device coach · works offline")
                .font(.ember(12, .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking").font(.ember(13, .semibold)).foregroundStyle(Theme.inkSoft)
            FlowLayout(spacing: 8) {
                ForEach(CoachAgent.suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s).font(.ember(14)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.line))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.top, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Ember Coach…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.ember(16))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.emberGradient, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || agent.isThinking)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func send(_ text: String) {
        let message = text
        draft = ""
        Task { await agent.send(message, store: store) }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onOpenPlan: (WorkoutPlan) -> Void
    var onStart: (WorkoutPlan) -> Void
    var onExercise: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 50) }
            if message.role == .coach {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.emberGradient, in: Circle())
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(.ember(15))
                    .foregroundStyle(message.role == .user ? Color.white : Theme.ink)
                    .textSelection(.enabled)
                if let plan = message.plan, !plan.items.isEmpty { planCard(plan) }
                if let id = message.exerciseID, let ex = ExerciseLibrary.exercise(id) { exerciseCard(ex) }
            }
            .padding(12)
            .background {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.emberGradient)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line))
                }
            }
            if message.role == .coach { Spacer(minLength: 24) }
        }
    }

    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.title.capitalizedFirst).font(.ember(15, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(Fmt.clock(plan.totalSeconds)).font(.ember(13, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: -10) {
                ForEach(plan.items.prefix(6)) { item in
                    ExerciseThumb(exercise: item.exercise, size: 40)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.surface, lineWidth: 2))
                }
                if plan.items.count > 6 {
                    Text("+\(plan.items.count - 6)").font(.ember(12, .bold)).foregroundStyle(Theme.inkSoft)
                        .padding(.leading, 16)
                }
            }
            HStack(spacing: 8) {
                Button { onStart(plan) } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(EmberButtonStyle(kind: .primary, compact: true))
                Button { onOpenPlan(plan) } label: { Text("View plan") }
                    .buttonStyle(EmberButtonStyle(kind: .secondary, compact: true))
            }
        }
        .padding(12)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func exerciseCard(_ ex: Exercise) -> some View {
        Button { onExercise(ex.id) } label: {
            HStack(spacing: 12) {
                ExerciseThumb(exercise: ex, size: 56, animated: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                    Text("Animation, steps & video demos").font(.ember(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }
            .padding(10)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * 4
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.inkSoft)
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * abs(sin(t + Double(i) * 0.7)))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.line))
        .padding(.leading, 36)
        .accessibilityLabel("Coach is typing")
    }
}
