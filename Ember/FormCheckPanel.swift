import AVFoundation
import SwiftUI
import UIKit

struct FormCheckPanel: View {
    let exerciseId: String
    @State private var model = FormCheckModel()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            camera
            if model.availability == .running || model.availability == .starting {
                PoseOverlay(joints: model.joints)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack {
                    HStack {
                        Spacer()
                        if let url = ExercisePreviewCatalog.url(for: exerciseId) {
                            VStack(spacing: 4) {
                                ReferenceClip(url: url)
                                    .frame(width: 112, height: 63)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.85), lineWidth: 1)
                                    )
                                Text("Reference")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(8)
                            .accessibilityLabel("Reference clip for \(exerciseId)")
                        }
                    }
                    Spacer()
                    banner
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(EmberColor.ink)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { model.start(exerciseId: exerciseId) }
        .onDisappear { model.stop() }
        .onChange(of: exerciseId) { _, newValue in
            model.setExercise(newValue)
        }
    }

    @ViewBuilder
    private var camera: some View {
        switch model.availability {
        case .running, .starting:
            CameraPreview(session: model.session)
        case .requesting:
            status("Asking for the camera…", detail: "Video stays on this phone.", settings: false)
        case .denied:
            status("Camera access is off.", detail: "You can keep going without Form Check.", settings: true)
        case .unavailable:
            status("No camera on this iPhone.", detail: "You can keep going without Form Check.", settings: false)
        case .idle:
            Color.black
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bannerTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(toneColor)
            Text(bannerDetail)
                .font(.caption)
                .foregroundStyle(.white)
            Text(FormEvaluator.reference(for: exerciseId))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.45))
    }

    private var bannerTitle: String {
        switch model.availability {
        case .starting, .requesting:
            "Starting the camera…"
        default:
            model.feedback.title
        }
    }

    private var bannerDetail: String {
        switch model.availability {
        case .starting, .requesting:
            "Video stays on this phone."
        default:
            model.feedback.detail
        }
    }

    private var toneColor: Color {
        switch model.feedback.tone {
        case .good:
            Color(red: 0.62, green: 0.84, blue: 0.62)
        case .adjust:
            EmberColor.accent
        case .searching, .guide:
            .white
        }
    }

    private func status(_ title: String, detail: String, settings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            if settings {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }
}

private struct PoseOverlay: View {
    var joints: [PoseJoint: PosePoint]

    private static let links: [(PoseJoint, PoseJoint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.leftShoulder, .nose),
        (.rightShoulder, .nose)
    ]

    var body: some View {
        Canvas { context, size in
            func placed(_ joint: PoseJoint) -> CGPoint? {
                guard let point = joints[joint], point.confidence >= FormEvaluator.minimumConfidence else { return nil }
                return CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
            }
            var path = Path()
            for (start, end) in Self.links {
                guard let a = placed(start), let b = placed(end) else { continue }
                path.move(to: a)
                path.addLine(to: b)
            }
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for joint in PoseJoint.allCases {
                guard let point = placed(joint) else { continue }
                let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewHost {
        let view = CameraPreviewHost()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewHost, context: Context) {
        uiView.previewLayer.session = session
        uiView.applyConnection()
    }
}

private final class CameraPreviewHost: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        applyConnection()
    }

    func applyConnection() {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        let front = sessionPosition == .front
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = front
        }
    }

    private var sessionPosition: AVCaptureDevice.Position {
        previewLayer.session?.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first?
            .device
            .position ?? .front
    }
}

private struct ReferenceClip: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                SilentPlayer(player: player, gravity: .resizeAspectFill)
            } else {
                EmberColor.ink
            }
        }
        .onAppear(perform: start)
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            item.seek(to: .zero) { _ in
                Task { @MainActor in
                    player?.play()
                }
            }
        }
    }

    private func start() {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        player.play()
    }
}

struct SilentPlayer: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> SilentPlayerHost {
        let view = SilentPlayerHost()
        view.playerLayer.videoGravity = gravity
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: SilentPlayerHost, context: Context) {
        uiView.playerLayer.videoGravity = gravity
        uiView.playerLayer.player = player
    }
}

final class SilentPlayerHost: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.984, green: 0.965, blue: 0.941, alpha: 1)
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
