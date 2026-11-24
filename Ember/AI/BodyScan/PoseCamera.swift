import AVFoundation
import SwiftUI
import Vision

/// Front camera + Apple Vision body-pose detection. Everything stays on-device; frames are never stored.
final class PoseCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum CameraState: Equatable {
        case idle, unauthorized, unavailable, running
    }

    @Published private(set) var state: CameraState = .idle
    @Published private(set) var pose: BodyPose?
    /// Size of the (portrait, mirrored) frames, used to align the overlay with the preview.
    @Published private(set) var frameSize = CGSize(width: 720, height: 1280)

    /// Called on the main thread for every analysed frame.
    var onPose: ((BodyPose?) -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.ember.camera", qos: .userInitiated)
    private let request = VNDetectHumanBodyPoseRequest()
    private var configured = false
    private var frameCounter = 0

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() } else { self?.state = .unauthorized }
                }
            }
        default:
            state = .unauthorized
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        if state == .running { state = .idle }
    }

    private func configureAndRun() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable
            return
        }
        let isFront = device.position == .front
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = self.session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
                if self.session.canAddInput(input) { self.session.addInput(input) }
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(output) { self.session.addOutput(output) }
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = isFront
                    }
                }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        // ~15 analyses per second is plenty and saves battery.
        guard frameCounter % 2 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let size = CGSize(width: width, height: height)
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        var detected: BodyPose?
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                detected = BodyPose(observation: observation, aspect: CGFloat(width) / CGFloat(max(1, height)))
            }
        } catch {
            detected = nil
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.frameSize != size { self.frameSize = size }
            self.pose = detected
            self.onPose?(detected)
        }
    }
}

// MARK: - Preview + overlay

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Draws the detected skeleton over an aspect-fill preview.
struct SkeletonOverlay: View {
    var pose: BodyPose?
    var frameSize: CGSize
    var tint: Color = Theme.ember

    var body: some View {
        Canvas { ctx, size in
            guard let pose else { return }
            let scale = max(size.width / frameSize.width, size.height / frameSize.height)
            let drawn = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
            let ox = (size.width - drawn.width) / 2, oy = (size.height - drawn.height) / 2
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * drawn.width, y: oy + p.y * drawn.height) }

            for (a, b) in Joint.bones {
                guard let pa = pose.points[a], let pb = pose.points[b] else { continue }
                var path = Path()
                path.move(to: map(pa))
                path.addLine(to: map(pb))
                ctx.stroke(path, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            for (_, p) in pose.points {
                let c = map(p)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(tint))
            }
        }
        .allowsHitTesting(false)
    }
}
