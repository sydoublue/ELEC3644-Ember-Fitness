import AVFoundation
import SwiftUI

/// Short offline preview shown before a work bout. Skip starts the timer immediately.
struct ExercisePreviewView: View {
    let exerciseId: String
    let name: String
    let cue: String
    let onFinished: () -> Void
    let onEnd: () -> Void

    @State private var player: AVPlayer?
    @State private var didFinish = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PREVIEW")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(EmberColor.accent)
            Text(name)
                .font(.largeTitle.bold())
                .foregroundStyle(EmberColor.ink)
            media
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(EmberColor.paper)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of \(name)")
            Text(cue)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Timer starts after this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Skip preview", action: finish)
                .buttonStyle(EmberSecondaryButton())
            Button("End workout", action: onEnd)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(EmberColor.paper)
        .task(id: exerciseId) {
            let seconds: Double = previewURL == nil ? 2.5 : 4
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            finish()
        }
        .onAppear(perform: startPlayer)
        .onDisappear {
            player?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            finish()
        }
    }

    private var previewURL: URL? {
        ExercisePreviewCatalog.url(for: exerciseId)
    }

    @ViewBuilder
    private var media: some View {
        if let player {
            SilentPlayer(player: player)
        } else if previewURL == nil {
            PreviewFallback()
        } else {
            EmberColor.paper
        }
    }

    private func startPlayer() {
        guard player == nil, let url = previewURL else { return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        player.play()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        player?.pause()
        onFinished()
    }
}

/// Drawn stand-in used only when a bundled clip is missing. Still offline.
private struct PreviewFallback: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let bend = (sin(timeline.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
            Canvas { context, size in
                let mid = size.width / 2
                let base = size.height * 0.72
                func at(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: mid + x, y: y)
                }
                let hipY = base - 70 - bend * 24
                let head = at(0, hipY - 78)
                let shoulder = at(0, hipY - 46)
                let hip = at(-bend * 12, hipY)
                let knee = at(16 + bend * 22, hipY + 46)
                let ankle = at(6, base)
                let wrist = at(34 + bend * 28, hipY - 8)
                var path = Path()
                path.move(to: shoulder)
                path.addLine(to: hip)
                path.addLine(to: knee)
                path.addLine(to: ankle)
                path.move(to: shoulder)
                path.addLine(to: wrist)
                context.stroke(path, with: .color(EmberColor.ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                context.fill(
                    Path(ellipseIn: CGRect(x: head.x - 12, y: head.y - 12, width: 24, height: 24)),
                    with: .color(EmberColor.ink)
                )
            }
            .background(EmberColor.paper)
        }
    }
}
