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
                        if let exercise = ExerciseLibrary.exercise(exerciseId) {
                            VStack(spacing: 4) {
                                ExerciseFigureView(motion: exercise.motion, tint: .white, animated: true)
                                    .frame(width: 80, height: 80)
                                    .padding(4)
                                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(.white.opacity(0.85), lineWidth: 1)
                                    )
                                Text("Reference")
                                    .font(.ember(11, .semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(8)
                            .accessibilityLabel("Reference demo for \(exercise.name)")
                        }
                    }
                    Spacer()
                    banner
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(Theme.ink)
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
            FormCheckPreview(session: model.session)
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
            Theme.ember
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

private struct FormCheckPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> FormCheckPreviewHost {
        let view = FormCheckPreviewHost()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: FormCheckPreviewHost, context: Context) {
        uiView.previewLayer.session = session
        uiView.applyConnection()
    }
}

private final class FormCheckPreviewHost: UIView {
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
