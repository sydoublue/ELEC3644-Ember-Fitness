import SwiftUI
import AVFoundation

// MARK: - Tab home

struct BodyScanHomeView: View {
    @Environment(EmberStore.self) private var store
    @State private var scanning = false
    @State private var viewing: BodyScanResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    howItWorks
                    if let latest = store.latestScan {
                        SectionHeader(title: "Latest result")
                        ScanSummaryCard(result: latest) { viewing = latest }
                    }
                    if store.scans.count > 1 {
                        SectionHeader(title: "History")
                        VStack(spacing: 0) {
                            ForEach(store.scans.sorted { $0.date > $1.date }.dropFirst()) { scan in
                                Button { viewing = scan } label: {
                                    HStack {
                                        Text(Fmt.relativeDay(scan.date)).font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                                        if scan.isSample { Text("Sample").font(.ember(11)).foregroundStyle(Theme.inkSoft) }
                                        Spacer()
                                        Text("\(scan.score)").font(.ember(17, .bold)).foregroundStyle(Theme.ember)
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
                                    }
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.line)
                            }
                        }
                        .emberCard(padding: 12)
                    }
                    Text("Body Scan looks at posture and movement patterns for exercise suggestions. It is not a medical assessment.")
                        .font(.ember(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .emberBackground()
            .navigationTitle("Body Scan")
            .fullScreenCover(isPresented: $scanning) { ScanSessionView() }
            .sheet(item: $viewing) { result in
                NavigationStack { ScanResultView(result: result, onBuild: { viewing = nil }) }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI · ON-DEVICE", systemImage: "sparkles")
                        .font(.ember(12, .bold)).tracking(1.1)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Scan your body,\nget your best moves")
                        .font(.ember(24, .bold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Text("About 60 seconds. Your camera tracks 19 points on your body to check posture, reach and squat form.")
                .font(.ember(14)).foregroundStyle(.white.opacity(0.9))
            Button { scanning = true } label: {
                Label("Start scan", systemImage: "camera.viewfinder")
                    .font(.ember(17, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(Theme.calm)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(20)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Theme.calm, Color(hex: 0x6A4FD9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                ScanFigureGlyph()
                    .frame(width: 150, height: 190)
                    .offset(x: 20, y: -10)
                    .opacity(0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.calm.opacity(0.3), radius: 20, y: 10)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            step(1, "Stand tall", "Checks shoulder, hip and head alignment.", "figure.stand")
            step(2, "Reach overhead", "Measures how far and how evenly your arms reach.", "figure.arms.open")
            step(3, "Three squats", "Counts reps live and checks depth, knee tracking and balance.", "figure.cross.training")
            step(4, "Your plan", "Findings turn into exercise picks and a workout built for you.", "sparkles")
        }
        .emberCard()
    }

    private func step(_ n: Int, _ title: String, _ text: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.calm)
                .frame(width: 36, height: 36)
                .background(Theme.calm.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)").font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.ember(13)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// Decorative skeleton used on the scan hero.
struct ScanFigureGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let pose = BodyPose.sampleStanding
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - 0.2) / 0.6 * size.width, y: (p.y - 0.08) / 0.84 * size.height) }
            for (a, b) in Joint.bones {
                guard let pa = pose.points[a], let pb = pose.points[b] else { continue }
                var path = Path()
                path.move(to: map(pa)); path.addLine(to: map(pb))
                ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            for (_, p) in pose.points {
                let c = map(p)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.white))
            }
        }
    }
}

struct ScanSummaryCard: View {
    let result: BodyScanResult
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RingProgress(progress: Double(result.score) / 100, lineWidth: 8)
                    Text("\(result.score)").font(.ember(22, .bold)).foregroundStyle(Theme.ink)
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Fmt.relativeDay(result.date)).font(.ember(13)).foregroundStyle(Theme.inkSoft)
                        if result.isSample {
                            Text("SAMPLE").font(.ember(10, .bold)).foregroundStyle(Theme.warn)
                        }
                    }
                    Text(result.findings.isEmpty ? "Moving well" : "\(result.findings.count) things to work on")
                        .font(.ember(17, .bold)).foregroundStyle(Theme.ink)
                    Text(result.findings.prefix(2).map(\.title).joined(separator: " · "))
                        .font(.ember(13)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }
            .emberCard()
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Live scan

struct ScanSessionView: View {
    @Environment(EmberStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @StateObject private var camera = PoseCamera()
    @State private var controller = BodyScanController()
    @State private var cues = CueSpeaker()
    @State private var finished: BodyScanResult?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let finished {
                NavigationStack {
                    ScanResultView(result: finished, onBuild: { dismiss() })
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                        }
                }
                .transition(.move(edge: .bottom))
            } else {
                switch camera.state {
                case .unauthorized: permissionView
                case .unavailable: unavailableView
                default: liveView
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: finished != nil)
        .onAppear {
            cues.voiceEnabled = store.settings.voiceCues
            cues.hapticsEnabled = store.settings.haptics
            UIApplication.shared.isIdleTimerDisabled = true
            let controller = self.controller
            let cues = self.cues
            camera.onPose = { pose in controller.feed(pose) }
            controller.onStepChange = { step in
                cues.success()
                if step == .done {
                    if let result = controller.result { complete(result) }
                } else {
                    cues.say(step.instruction)
                }
            }
            controller.onRep = { n in
                cues.tap(.heavy)
                cues.say("\(n)")
            }
            camera.start()
            cues.say(BodyScanController.Step.position.instruction)
        }
        .onDisappear {
            camera.stop()
            cues.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func complete(_ result: BodyScanResult) {
        camera.stop()
        store.add(scan: result)
        cues.say(result.findings.isEmpty ? "Scan complete. You're moving well." :
                    "Scan complete. I found \(result.findings.count) things to work on.")
        finished = result
    }

    private var liveView: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            SkeletonOverlay(pose: camera.pose, frameSize: camera.frameSize,
                            tint: controller.bodyVisible ? Theme.good : Theme.ember)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close scan")
                    Spacer()
                    stepDots
                    Spacer()
                    Button("Skip") { controller.skipStep() }
                        .font(.ember(15, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                instructionCard
                Spacer()
                if controller.step == .squat {
                    repCounter
                }
                if !controller.bodyVisible && controller.step != .reach && controller.step != .done {
                    Label("Make sure your whole body, head to feet, is in view", systemImage: "viewfinder")
                        .font(.ember(14, .semibold)).foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(16)
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach([BodyScanController.Step.position, .stand, .reach, .squat], id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= controller.step.rawValue ? Color.white : Color.white.opacity(0.3))
                    .frame(width: s == controller.step ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3), value: controller.step)
    }

    private var instructionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RingProgress(progress: controller.progress, lineWidth: 6,
                             tint: AnyShapeStyle(Theme.good), track: .white.opacity(0.25))
                Image(systemName: icon(for: controller.step)).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.step.title).font(.ember(20, .bold)).foregroundStyle(.white)
                Text(controller.step.instruction).font(.ember(14)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut, value: controller.step)
    }

    private func icon(for step: BodyScanController.Step) -> String {
        switch step {
        case .position: return "viewfinder"
        case .stand: return "figure.stand"
        case .reach: return "figure.arms.open"
        case .squat: return "figure.cross.training"
        case .done: return "checkmark"
        }
    }

    private var repCounter: some View {
        VStack(spacing: 2) {
            Text("\(controller.reps)")
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring, value: controller.reps)
            Text("of \(BodyScanController.targetReps) reps").font(.ember(15, .semibold)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(.white)
            Text("Camera access needed").font(.ember(22, .bold)).foregroundStyle(.white)
            Text("Body Scan analyses your movement live on your phone. Nothing is recorded or uploaded.")
                .font(.ember(15)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(EmberButtonStyle(kind: .primary, compact: true))
            Button("Close") { dismiss() }.foregroundStyle(.white.opacity(0.8))
        }
        .padding(32)
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill").font(.system(size: 44)).foregroundStyle(.white)
            Text("No camera found").font(.ember(22, .bold)).foregroundStyle(.white)
            Text("Body Scan needs a real iPhone camera. You can preview what a result looks like with sample data.")
                .font(.ember(15)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            Button("See a sample result") { complete(BodyScanAnalyzer.sampleResult) }
                .buttonStyle(EmberButtonStyle(kind: .primary, compact: true))
            Button("Close") { dismiss() }.foregroundStyle(.white.opacity(0.8))
        }
        .padding(32)
    }
}

// MARK: - Result

struct ScanResultView: View {
    let result: BodyScanResult
    var onBuild: () -> Void
    @Environment(EmberStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var detail: Exercise?
    @State private var animate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                scoreHeader
                if result.isSample {
                    InfoBanner(text: "This is sample data to show how results look. Run the scan on an iPhone for your own.",
                               symbol: "exclamationmark.circle.fill", tint: Theme.warn)
                }
                findingsSection
                exercisesSection
                Button {
                    var input = store.suggestedSetup()
                    input.focus = result.focusCategories
                    input.preferredExercises = result.recommendedExerciseIDs
                    onBuild()
                    router.openSetup(prefill: input)
                } label: {
                    Label("Build my workout", systemImage: "sparkles")
                }
                .buttonStyle(.emberPrimary)
                Text("Measurements are estimates from a 2D camera and can vary with lighting, clothing and angle. Not a medical assessment.")
                    .font(.ember(12)).foregroundStyle(Theme.inkSoft)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .emberBackground()
        .navigationTitle("Your scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.easeOut(duration: 1.0).delay(0.2)) { animate = true } }
        .sheet(item: $detail) { ex in
            NavigationStack {
                ExerciseDetailView(exerciseID: ex.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
            }
        }
    }

    private var scoreHeader: some View {
        HStack(spacing: 20) {
            ZStack {
                RingProgress(progress: animate ? Double(result.score) / 100 : 0, lineWidth: 14)
                VStack(spacing: 0) {
                    Text("\(result.score)").font(.ember(40, .bold)).foregroundStyle(Theme.ink)
                    Text("movement").font(.ember(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.ember(22, .bold)).foregroundStyle(Theme.ink)
                Text(result.findings.isEmpty
                     ? "No big imbalances spotted. Time to progress."
                     : "Ember picked exercises to target \(result.findings.count == 1 ? "this" : "these").")
                    .font(.ember(14)).foregroundStyle(Theme.inkSoft)
                if result.metrics.squatReps > 0 {
                    Label("\(result.metrics.squatReps) squats tracked", systemImage: "checkmark.circle.fill")
                        .font(.ember(13, .semibold)).foregroundStyle(Theme.good)
                }
            }
        }
        .emberCard()
    }

    private var headline: String {
        switch result.score {
        case 90...: return "Moving really well"
        case 75..<90: return "Solid foundation"
        case 60..<75: return "A few things to tune"
        default: return "Lots of room to grow"
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Ember noticed").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            if result.findings.isEmpty {
                InfoBanner(text: "Shoulders and hips level, good reach and a controlled squat.", symbol: "checkmark.seal.fill", tint: Theme.good)
            }
            ForEach(result.findings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: finding.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                        .frame(width: 38, height: 38)
                        .background(Theme.warn.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.title).font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                        Text(result.detail(for: finding)).font(.ember(13, .medium)).foregroundStyle(Theme.warn)
                        Text(finding.why).font(.ember(13)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .emberCard(padding: 14)
            }
        }
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best exercises for you").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(result.recommendedExerciseIDs.compactMap(ExerciseLibrary.exercise), id: \.id) { ex in
                        Button { detail = ex } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ExerciseFigureView(motion: ex.motion, tint: Theme.color(for: ex.category))
                                    .frame(width: 130, height: 130)
                                    .background(Theme.color(for: ex.category).opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Text(ex.name).font(.ember(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(ex.isRecovery ? "Recovery" : ex.category.title)
                                    .font(.ember(12)).foregroundStyle(Theme.inkSoft)
                            }
                            .frame(width: 130)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
