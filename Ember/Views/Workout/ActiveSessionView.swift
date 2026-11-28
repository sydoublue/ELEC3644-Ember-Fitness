import SwiftUI
import UIKit

/// Full-screen workout: Active session → Feedback.
struct WorkoutFlowView: View {
    let plan: WorkoutPlan
    @Environment(EmberStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var player: SessionPlayer
    @State private var cues = CueSpeaker()
    @State private var finishedSession: Session?

    init(plan: WorkoutPlan) {
        self.plan = plan
        _player = State(initialValue: SessionPlayer(plan: plan))
    }

    var body: some View {
        ZStack {
            if let session = finishedSession {
                FeedbackView(session: session, plan: plan) { feedback in
                    if let feedback { store.save(feedback: feedback) }
                    router.finishWorkout()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ActiveSessionView(player: player)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: finishedSession != nil)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            cues.voiceEnabled = store.settings.voiceCues
            cues.hapticsEnabled = store.settings.haptics
            let player = self.player
            let cues = self.cues
            player.onEvent = { event in
                cues.handle(event, player: player)
                if case .finished = event { complete() }
            }
            player.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            player.stop()
            cues.stop()
        }
    }

    private func complete() {
        guard finishedSession == nil else { return }
        let session = player.makeSession()
        store.record(session: session, plan: plan)
        finishedSession = session
    }
}

/// Active view (proposal §2.3): one exercise at a time, timer, next up, skip / rest controls.
struct ActiveSessionView: View {
    let player: SessionPlayer
    @State private var confirmEnd = false
    @State private var howTo: Exercise?
    @State private var wasPausedBeforeHowTo = false
    @State private var showFormCheck = false

    private var displayItem: PlanItem? {
        switch player.phase {
        case .rest: return player.upNext ?? player.current
        default: return player.current
        }
    }

    private var phaseTint: Color {
        switch player.phase {
        case .getReady: return Theme.calm
        case .work: return displayItem.map { Theme.color(for: $0.exercise.category) } ?? Theme.ember
        case .rest: return Theme.good
        case .finished: return Theme.ember
        }
    }

    private var phaseLabel: String {
        switch player.phase {
        case .getReady: return "GET READY"
        case .work:
            if player.current?.isRecovery == true { return "RECOVERY · OPTIONAL" }
            return player.isRepWork ? "REPS" : "WORK"
        case .rest: return "REST"
        case .finished: return "DONE"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 18) {
                    if showFormCheck, player.phase == .work, let item = player.current {
                        FormCheckPanel(exerciseId: item.exerciseID)
                    } else {
                        figure
                    }
                    titleBlock
                    timer
                    nextUp
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            controls
        }
        .background {
            ZStack {
                Theme.background
                RadialGradient(colors: [phaseTint.opacity(0.22), Theme.background.opacity(0)],
                               center: .top, startRadius: 20, endRadius: 520)
                    .animation(.easeInOut(duration: 0.6), value: player.phase)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save progress", role: .destructive) { player.endEarly() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Anything you haven't done will be logged as skipped.")
        }
        .onChange(of: player.phase) { _, phase in
            if phase != .work { showFormCheck = false }
        }
        .sheet(item: $howTo, onDismiss: {
            if !wasPausedBeforeHowTo && player.isPaused { player.togglePause() }
        }) { ex in
            NavigationStack {
                ExerciseDetailView(exerciseID: ex.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Resume") { howTo = nil } } }
            }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button { confirmEnd = true } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40).background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("End workout")
                Spacer()
                Text(player.plan.title.capitalizedFirst).font(.ember(15, .semibold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill").font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40).background(Theme.surface, in: Circle())
                }
                .accessibilityLabel(player.isPaused ? "Resume" : "Pause")
            }
            .foregroundStyle(Theme.ink)
            // Segmented progress
            HStack(spacing: 4) {
                ForEach(player.plan.items) { item in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(item.isRecovery ? Theme.good : Theme.color(for: item.exercise.category))
                                .frame(width: geo.size.width * fill(for: item))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func fill(for item: PlanItem) -> CGFloat {
        if item.id < player.index { return 1 }
        if item.id > player.index { return 0 }
        switch player.phase {
        case .work: return CGFloat(player.phaseProgress)
        case .rest, .finished: return 1
        case .getReady: return 0
        }
    }

    private var figure: some View {
        Group {
            if let item = displayItem {
                ExerciseFigureView(motion: item.exercise.motion, tint: phaseTint, animated: player.phase == .work && !player.isPaused)
                    .padding(18)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        VStack(alignment: .trailing, spacing: 8) {
                            Button {
                                wasPausedBeforeHowTo = player.isPaused
                                if !player.isPaused { player.togglePause() }
                                howTo = item.exercise
                            } label: {
                                Label("How to", systemImage: "play.rectangle.fill")
                                    .font(.ember(13, .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.surface, in: Capsule())
                                    .overlay(Capsule().stroke(Theme.line))
                            }
                            if player.phase == .work {
                                Button {
                                    showFormCheck.toggle()
                                } label: {
                                    Label(showFormCheck ? "Demo" : "Form Check",
                                          systemImage: showFormCheck ? "figure.cooldown" : "camera.viewfinder")
                                        .font(.ember(13, .semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Theme.surface, in: Capsule())
                                        .overlay(Capsule().stroke(Theme.line))
                                }
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(12)
                    }
                    .id(item.exerciseID)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: displayItem?.exerciseID)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(phaseLabel)
                .font(.ember(13, .bold)).tracking(1.5)
                .foregroundStyle(phaseTint)
            Text(player.phase == .rest ? "Next: \(displayItem?.exercise.name ?? "")" : (displayItem?.exercise.name ?? ""))
                .font(.ember(28, .bold)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let ex = displayItem?.exercise {
                Text(ex.instruction + (ex.perSide ? " Switch sides halfway." : ""))
                    .font(.ember(15)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var timer: some View {
        ZStack {
            RingProgress(progress: player.isRepWork ? player.phaseProgress : 1 - player.phaseProgress, lineWidth: 14,
                         tint: AnyShapeStyle(phaseTint))
            VStack(spacing: 2) {
                if player.isRepWork {
                    Text("\(player.loggedReps)/\(player.targetReps)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                        .animation(.default, value: player.loggedReps)
                    Text(player.current?.exercise.perSide == true ? "each side" : "reps")
                        .font(.ember(14, .semibold)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(Fmt.clock(player.remainingWholeSeconds))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: player.remainingWholeSeconds)
                }
                if player.isPaused {
                    Text("Paused").font(.ember(14, .semibold)).foregroundStyle(Theme.warn)
                }
            }
        }
        .frame(width: 190, height: 190)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(player.isRepWork
                            ? "\(player.loggedReps) of \(player.targetReps) reps"
                            : "\(player.remainingWholeSeconds) seconds left")
    }

    @ViewBuilder private var nextUp: some View {
        if player.phase == .work, let next = player.upNext {
            HStack(spacing: 12) {
                ExerciseThumb(exercise: next.exercise, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT").font(.ember(11, .bold)).tracking(1).foregroundStyle(Theme.inkSoft)
                    Text(next.exercise.name).font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            .emberCard(padding: 10)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            switch player.phase {
            case .rest:
                Button { player.skipBreak() } label: { Text("I'm good, skip the break") }
                    .buttonStyle(.emberPrimary)
                Button { player.addRest() } label: {
                    Text(player.extraRestUsed ? "Extra rest added" : "Need more rest (+15s)")
                }
                .buttonStyle(.emberSecondary)
                .disabled(player.extraRestUsed)
                .opacity(player.extraRestUsed ? 0.5 : 1)
            case .getReady:
                Button { player.skipExercise() } label: { Text("I'm ready, go") }
                    .buttonStyle(.emberPrimary)
            case .work:
                if player.isRepWork {
                    Button { player.logRep() } label: { Text("Log a rep") }
                        .buttonStyle(.emberPrimary)
                    Button { player.completeCurrentExercise() } label: { Text("Done with this set") }
                        .buttonStyle(.emberSecondary)
                }
                Button { player.skipExercise() } label: {
                    Label(player.current?.isRecovery == true ? "Skip recovery" : "Skip exercise", systemImage: "forward.fill")
                }
                .buttonStyle(.emberSecondary)
            case .finished:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.25), value: player.phase)
    }
}
