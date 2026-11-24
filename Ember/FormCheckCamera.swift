import AVFoundation
import CoreVideo
import ImageIO
import Observation
import Vision

enum CameraAvailability: Equatable {
    case idle
    case requesting
    case starting
    case running
    case denied
    case unavailable
}

/// On-device pose camera. Frames stay in memory for Vision and are dropped.
/// Nothing is recorded, cached, or uploaded.
nonisolated final class PoseCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ember.formcheck.session")
    private let visionQueue = DispatchQueue(label: "ember.formcheck.vision")
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let stateLock = NSLock()
    private var continuation: AsyncStream<PoseSnapshot>.Continuation?
    private var exerciseId = ""
    private var visionOrientation: CGImagePropertyOrientation = .leftMirrored
    private var configured = false
    private var frameIndex = 0

    var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    func setExercise(_ id: String) {
        stateLock.lock()
        exerciseId = id
        stateLock.unlock()
    }

    func start() -> AsyncStream<PoseSnapshot> {
        finishContinuation()
        let stream = AsyncStream<PoseSnapshot>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.stateLock.lock()
            self.continuation = continuation
            self.stateLock.unlock()
        }
        sessionQueue.async { [weak self] in
            self?.configureAndStart()
        }
        return stream
    }

    func stop() {
        finishContinuation()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    deinit {
        finishContinuation()
        let session = session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        frameIndex += 1
        if frameIndex != 1 && frameIndex % 3 != 0 { return }
        yield(snapshot(from: sampleBuffer))
    }

    private func configureAndStart() {
        if configured {
            if !session.isRunning {
                session.startRunning()
            }
            return
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            finishContinuation()
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            finishContinuation()
            return
        }
        session.addOutput(output)
        // Front-camera buffers are mirrored so the overlay matches the preview.
        let orientation: CGImagePropertyOrientation = device.position == .front ? .leftMirrored : .right
        stateLock.lock()
        visionOrientation = orientation
        stateLock.unlock()
        session.commitConfiguration()
        configured = true
        session.startRunning()
    }

    private func snapshot(from sampleBuffer: CMSampleBuffer) -> PoseSnapshot {
        stateLock.lock()
        let orientation = visionOrientation
        let exerciseId = exerciseId
        stateLock.unlock()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([poseRequest])
        } catch {
            return PoseSnapshot(joints: [:], feedback: .noPerson)
        }
        guard let observation = poseRequest.results?.first else {
            return PoseSnapshot(joints: [:], feedback: .noPerson)
        }
        let joints = Self.joints(from: observation)
        let feedback = FormEvaluator.evaluate(exerciseId: exerciseId, joints: joints)
        return PoseSnapshot(joints: joints, feedback: feedback)
    }

    private static func joints(from observation: VNHumanBodyPoseObservation) -> [PoseJoint: PosePoint] {
        let names: [(PoseJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]
        var joints: [PoseJoint: PosePoint] = [:]
        for (joint, name) in names {
            guard let point = try? observation.recognizedPoint(name) else { continue }
            joints[joint] = PosePoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        return joints
    }

    private func yield(_ snapshot: PoseSnapshot) {
        stateLock.lock()
        let continuation = continuation
        stateLock.unlock()
        continuation?.yield(snapshot)
    }

    private func finishContinuation() {
        stateLock.lock()
        let continuation = continuation
        self.continuation = nil
        stateLock.unlock()
        continuation?.finish()
    }
}

@Observable
final class FormCheckModel {
    var joints: [PoseJoint: PosePoint] = [:]
    var feedback: FormFeedback = .noPerson
    var availability: CameraAvailability = .idle
    let session: AVCaptureSession

    private let camera = PoseCamera()
    private var listen: Task<Void, Never>?
    private var generation = 0
    private var exerciseId = ""

    init() {
        session = camera.session
    }

    func setExercise(_ id: String) {
        exerciseId = id
        camera.setExercise(id)
    }

    func start(exerciseId: String) {
        stop()
        let token = generation
        self.exerciseId = exerciseId
        camera.setExercise(exerciseId)
        guard camera.hasCamera else {
            availability = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            begin()
        case .notDetermined:
            availability = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, token == self.generation else { return }
                    if granted {
                        self.begin()
                    } else {
                        self.availability = .denied
                    }
                }
            }
        default:
            availability = .denied
        }
    }

    func stop() {
        generation += 1
        listen?.cancel()
        listen = nil
        camera.stop()
        joints = [:]
        feedback = .noPerson
        availability = .idle
    }

    private func begin() {
        generation += 1
        let token = generation
        availability = .starting
        let stream = camera.start()
        listen = Task { @MainActor [weak self] in
            for await snapshot in stream {
                guard let self, token == self.generation else { return }
                self.joints = snapshot.joints
                self.feedback = snapshot.feedback
                self.availability = .running
            }
            guard let self, token == self.generation, !Task.isCancelled else { return }
            if self.availability == .starting || self.availability == .running {
                self.availability = .unavailable
            }
        }
    }
}
