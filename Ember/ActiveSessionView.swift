import SwiftUI

struct ActiveSessionView: View {
    let plan: WorkoutPlan
    @Binding var path: NavigationPath
    @State private var engine: SessionEngine
    @State private var gate = PreviewGate()
    @State private var formCheckOn = false
    @State private var startedAt = Date.now
    @State private var didFinish = false

    init(plan: WorkoutPlan, path: Binding<NavigationPath>) {
        self.plan = plan
        _path = path
        _engine = State(initialValue: SessionEngine(items: plan.items))
    }

    var body: some View {
        Group {
            if let item = engine.currentItem, gate.isPreviewing(phase: engine.phase, index: engine.index) {
                let index = engine.index
                ExercisePreviewView(
                    exerciseId: item.exerciseId,
                    name: item.name,
                    cue: item.cue,
                    onFinished: { gate.acknowledge(index: index) },
                    onEnd: { apply { $0.endEarly() } }
                )
                .id(index)
            } else {
                sessionBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(EmberColor.paper)
        .navigationTitle("Active")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard !gate.isPreviewing(phase: engine.phase, index: engine.index) else { return }
            apply { $0.tick() }
        }
    }

    @ViewBuilder
    private var sessionBody: some View {
        if formCheckOn {
            ScrollView { sessionContent(expands: false) }
                .scrollIndicators(.hidden)
        } else {
            sessionContent(expands: true)
        }
    }

    private func sessionContent(expands: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(phaseTitle)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(EmberColor.accent)
            Text(headline)
                .font(.largeTitle.bold())
                .foregroundStyle(EmberColor.ink)
            Text(clock(engine.remaining))
                .font(.system(size: formCheckOn ? 56 : 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(EmberColor.ink)
            Text(cue)
                .font(.title3)
                .foregroundStyle(.secondary)
            if let next = engine.nextItemName, engine.phase == .work {
                Text("Next: \(next)")
                    .font(.headline)
            }
            if expands {
                Spacer(minLength: 0)
            }
            controls
            Button("End workout") {
                apply { $0.endEarly() }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .leading)
    }

    private var headline: String {
        switch engine.phase {
        case .work: engine.currentItem?.name ?? "Workout"
        case .rest: "Rest"
        case .finished: "Done"
        }
    }

    private var phaseTitle: String {
        switch engine.phase {
        case .work: "WORK"
        case .rest: "REST"
        case .finished: "DONE"
        }
    }

    private var cue: String {
        switch engine.phase {
        case .work: engine.currentItem?.cue ?? ""
        case .rest: "Next: \(engine.nextItemName ?? "feedback")"
        case .finished: "Saving this session."
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch engine.phase {
        case .work:
            if formCheckOn, let item = engine.currentItem {
                FormCheckPanel(exerciseId: item.exerciseId)
                    .id(item.id)
            }
            Button(formCheckOn ? "Hide Form Check" : "Form Check") {
                formCheckOn.toggle()
            }
            .buttonStyle(EmberSecondaryButton())
            .accessibilityHint(formCheckOn ? "Turns the camera off." : "Optional. Uses the camera on this phone.")
            Button("Skip") {
                apply { $0.skip() }
            }
            .buttonStyle(EmberSecondaryButton())
        case .rest:
            Button("I'm good, skip the break") {
                apply { $0.skipBreak() }
            }
            .buttonStyle(EmberPrimaryButton())
            Button("Need more rest") {
                apply { $0.moreRest() }
            }
            .buttonStyle(EmberSecondaryButton())
            .disabled(engine.extraRestUsed)
        case .finished:
            EmptyView()
        }
    }

    private func apply(_ change: (inout SessionEngine) -> Void) {
        change(&engine)
        guard engine.phase == .finished, !didFinish else { return }
        didFinish = true
        let session = engine.makeSession(plan: plan, startedAt: startedAt, endedAt: .now)
        path.append(Route.feedback(FinishedSession(plan: plan, session: session)))
    }
}
