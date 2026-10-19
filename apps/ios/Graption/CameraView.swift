//
//  CameraView.swift
//  Graption
//
//  Created by Arya Vaidya on 9/30/26.
//

import SwiftUI
import AVFoundation
import Accelerate
import Combine
import UIKit
import Vision
import MediaPipeTasksVision

nonisolated private struct OneEuroFilter {
    private let minCutoff: Double
    private let beta: Double
    private let derivativeCutoff: Double
    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTimestamp: Double?

    // Inputs are normalized (0...1) image coordinates, so beta is much larger than the
    // pixel-space defaults from the paper; otherwise the speed term never reduces lag.
    init(minCutoff: Double = 1.25, beta: Double = 8.0, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func filter(_ value: Double, at timestamp: Double) -> Double {
        guard let previousValue, let previousTimestamp else {
            self.previousValue = value
            self.previousTimestamp = timestamp
            return value
        }

        let deltaTime = max(timestamp - previousTimestamp, 1.0 / 120.0)
        let rawDerivative = (value - previousValue) / deltaTime
        let derivativeAlpha = smoothingFactor(deltaTime, cutoff: derivativeCutoff)
        let derivative = exponentialFilter(
            rawDerivative,
            previous: self.previousDerivative,
            alpha: derivativeAlpha
        )
        let valueAlpha = smoothingFactor(deltaTime, cutoff: minCutoff + beta * abs(derivative))
        let filteredValue = exponentialFilter(value, previous: previousValue, alpha: valueAlpha)

        self.previousValue = filteredValue
        self.previousDerivative = derivative
        self.previousTimestamp = timestamp
        return filteredValue
    }

    private func smoothingFactor(_ deltaTime: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / deltaTime)
    }

    private func exponentialFilter(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1.0 - alpha) * previous
    }
}

/// One face as published to the UI. `box` and `landmarks` are normalized to the full,
/// portrait-oriented frame with a top-left origin. `landmarks` is empty when the face was
/// detected but too small or occluded for MediaPipe to fit a mesh.
nonisolated struct FaceTrack: Identifiable, Sendable {
    let id: Int
    let box: CGRect
    let landmarks: [SIMD3<Float>]

    var hasLandmarks: Bool { !landmarks.isEmpty }
}

nonisolated private struct FaceMeasurement {
    let box: CGRect
    let landmarks: [SIMD3<Float>]
}

nonisolated private struct TrackedFace {
    let id: Int
    var box: CGRect
    var landmarks: [SIMD3<Float>] = []
    var velocity = CGPoint.zero
    var missedFrames = 0
    var xFilter = OneEuroFilter()
    var yFilter = OneEuroFilter()
    var widthFilter = OneEuroFilter()
    var heightFilter = OneEuroFilter()
    private var lastTimestamp: Double?

    init(id: Int, measurement: FaceMeasurement, timestamp: Double) {
        self.id = id
        self.box = measurement.box
        update(with: measurement, timestamp: timestamp)
    }

    mutating func update(with measurement: FaceMeasurement, timestamp: Double) {
        let filtered = CGRect(
            x: xFilter.filter(measurement.box.minX, at: timestamp),
            y: yFilter.filter(measurement.box.minY, at: timestamp),
            width: widthFilter.filter(measurement.box.width, at: timestamp),
            height: heightFilter.filter(measurement.box.height, at: timestamp)
        )
        if let lastTimestamp {
            let timeScale = max(timestamp - lastTimestamp, 1.0 / 120.0)
            velocity = CGPoint(
                x: (filtered.midX - box.midX) / timeScale,
                y: (filtered.midY - box.midY) / timeScale
            )
        }
        box = filtered
        landmarks = measurement.landmarks
        missedFrames = 0
        lastTimestamp = timestamp
    }

    mutating func predict(at timestamp: Double) {
        let deltaTime = max(timestamp - (lastTimestamp ?? timestamp), 1.0 / 120.0)
        let decay = pow(0.65, deltaTime * 15.0)
        box = box.offsetBy(
            dx: velocity.x * deltaTime * decay,
            dy: velocity.y * deltaTime * decay
        )
        velocity.x *= decay
        velocity.y *= decay
        // Landmarks from an older frame would no longer line up with the predicted box.
        landmarks = []
        missedFrames += 1
        lastTimestamp = timestamp
    }

    var output: FaceTrack { FaceTrack(id: id, box: box, landmarks: landmarks) }
}

/// Where MediaPipe looks for landmarks. Detection always uses Apple Vision.
nonisolated enum LandmarkMode: Sendable {
    /// One pass over the whole frame. Faces beyond roughly arm's length are tracked (from
    /// Vision) but get no landmarks.
    case fullFrame
    /// One pass per Vision face on a crop where the face fills the input, so far faces get
    /// landmarks too. Costs one small landmarker run per face. Currently selected; training
    /// extraction must crop the same way (see GRAPTION_CONTEXT.md §6).
    case faceCrops
}

/// Owns capture and per-frame inference off the main actor.
///
/// Detection uses Apple Vision rather than MediaPipe's bundled short-range BlazeFace, which
/// downsamples the whole frame to 128 px and loses faces beyond roughly arm's length. Vision
/// boxes drive tracking; MediaPipe landmarks are attached per `LandmarkMode`.
nonisolated final class FaceCaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    static let maxFaces = 4
    let landmarkMode: LandmarkMode
    /// Crop side as a multiple of the detected face size. MediaPipe's detector needs context
    /// around the face, and its mesh ROI is about 1.5x the face.
    private static let cropScale: CGFloat = 2.2
    private static let cropSide = 256
    private static let minFaceConfidence: Float = 0.5

    let session = AVCaptureSession()
    /// Called on the video queue after every processed frame.
    var onFaces: (([FaceTrack]) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.graption.camera.session")
    // Frames are processed synchronously here. With alwaysDiscardsLateVideoFrames, frames that
    // arrive while busy are dropped, so the pipeline always works on the newest frame.
    private let videoQueue = DispatchQueue(label: "com.graption.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()

    // Video-queue state.
    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()
    private let sequenceHandler = VNSequenceRequestHandler()
    private var faceLandmarker: FaceLandmarker?
    private var cropPool: CVPixelBufferPool?
    private var trackedFaces: [TrackedFace] = []
    private var nextTrackID = 0
    private var publishedEmpty = false
    private var lastLandmarkerTimestamp = -1

    init(landmarkMode: LandmarkMode) {
        self.landmarkMode = landmarkMode
    }

    // Back camera, up to 1080p, 15 fps
    func start(completion: @escaping @Sendable (Bool) -> Void) {
        sessionQueue.async { [self] in
            if !session.inputs.isEmpty {
                if !session.isRunning { session.startRunning() }
                completion(true)
                return
            }
            completion(configure())
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            videoQueue.async { [self] in
                trackedFaces.removeAll()
            }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
            return false
        }

        do {
            let options = FaceLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            switch landmarkMode {
            case .fullFrame:
                // Video mode is the synchronous form of live stream: MediaPipe tracks faces
                // between frames and skips its detector while tracking holds.
                options.runningMode = .video
                options.numFaces = Self.maxFaces
                options.minTrackingConfidence = 0.5
            case .faceCrops:
                // Image mode is stateless, so one landmarker can serve every face crop in turn.
                options.runningMode = .image
                // Two so a neighbor partly inside the crop can't displace the target face.
                options.numFaces = 2
            }
            options.minFaceDetectionConfidence = 0.5
            options.minFacePresenceConfidence = 0.5
            options.outputFaceBlendshapes = false
            options.outputFacialTransformationMatrixes = false
            let landmarker = try FaceLandmarker(options: options)
            let pool = landmarkMode == .faceCrops ? makeCropPool() : nil
            videoQueue.sync {
                faceLandmarker = landmarker
                cropPool = pool
            }
        } catch {
            print("MediaPipe setup error: \(error.localizedDescription)")
            return false
        }

        guard configureSession(device: device, input: input) else { return false }
        session.startRunning()
        return true
    }

    private func configureSession(device: AVCaptureDevice, input: AVCaptureDeviceInput) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            session.removeInput(input)
            return false
        }
        session.addOutput(videoOutput)

        // Rotate buffers to portrait so Vision, MediaPipe, and the preview share one frame.
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        configureCamera(for: device, fps: 15)
        return true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite else { return }

        let faces = updateTracking(with: detectFaces(in: pixelBuffer, timestamp: timestamp), timestamp: timestamp)
        // Skip repeated empty updates so an empty room doesn't re-render SwiftUI at 15 fps.
        if faces.isEmpty && publishedEmpty { return }
        publishedEmpty = faces.isEmpty
        onFaces?(faces)
    }

    // MARK: Detection

    private func detectFaces(in pixelBuffer: CVPixelBuffer, timestamp: Double) -> [FaceMeasurement] {
        let boxes = visionFaceBoxes(in: pixelBuffer)
        switch landmarkMode {
        case .faceCrops:
            return boxes.map { FaceMeasurement(box: $0, landmarks: landmarks(around: $0, in: pixelBuffer)) }
        case .fullFrame:
            return attach(fullFrameMeshes(in: pixelBuffer, timestamp: timestamp), to: boxes)
        }
    }

    private func visionFaceBoxes(in pixelBuffer: CVPixelBuffer) -> [CGRect] {
        do {
            try sequenceHandler.perform([faceRequest], on: pixelBuffer, orientation: .up)
        } catch {
            print("Vision face detection error: \(error.localizedDescription)")
            return []
        }

        let observations = (faceRequest.results ?? [])
            .filter { $0.confidence >= Self.minFaceConfidence }
            .sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
            .prefix(Self.maxFaces)

        return observations.map { observation in
            // Vision uses a bottom-left origin; everything downstream uses top-left.
            let visionBox = observation.boundingBox
            return CGRect(
                x: visionBox.minX,
                y: 1 - visionBox.maxY,
                width: visionBox.width,
                height: visionBox.height
            )
        }
    }

    /// Runs MediaPipe once on the whole frame and returns every mesh it found.
    private func fullFrameMeshes(in pixelBuffer: CVPixelBuffer, timestamp: Double) -> [[SIMD3<Float>]] {
        guard let faceLandmarker else { return [] }
        // Video mode rejects non-increasing timestamps.
        let timestampInMilliseconds = Int(timestamp * 1_000)
        guard timestampInMilliseconds > lastLandmarkerTimestamp else { return [] }
        lastLandmarkerTimestamp = timestampInMilliseconds

        do {
            let result = try faceLandmarker.detect(
                videoFrame: try MPImage(pixelBuffer: pixelBuffer),
                timestampInMilliseconds: timestampInMilliseconds
            )
            return result.faceLandmarks.map { face in face.map { SIMD3($0.x, $0.y, $0.z) } }
        } catch {
            print("MediaPipe detection error: \(error.localizedDescription)")
            return []
        }
    }

    /// Pairs each Vision box with the mesh whose nose tip falls inside it. Meshes Vision
    /// missed still become measurements, boxed by their landmarks.
    private func attach(_ meshes: [[SIMD3<Float>]], to boxes: [CGRect]) -> [FaceMeasurement] {
        var unclaimed = meshes.filter { $0.count > 1 }
        var measurements = boxes.map { box -> FaceMeasurement in
            let searchArea = box.insetBy(dx: -box.width * 0.25, dy: -box.height * 0.25)
            let match = unclaimed.indices
                .map { index in (index, CGPoint(x: CGFloat(unclaimed[index][1].x), y: CGFloat(unclaimed[index][1].y))) }
                .filter { searchArea.contains($0.1) }
                .min { hypot($0.1.x - box.midX, $0.1.y - box.midY) < hypot($1.1.x - box.midX, $1.1.y - box.midY) }
            guard let match else { return FaceMeasurement(box: box, landmarks: []) }
            return FaceMeasurement(box: box, landmarks: unclaimed.remove(at: match.0))
        }
        for mesh in unclaimed where measurements.count < Self.maxFaces {
            measurements.append(FaceMeasurement(box: boundingBox(of: mesh), landmarks: mesh))
        }
        return measurements
    }

    private func boundingBox(of mesh: [SIMD3<Float>]) -> CGRect {
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for landmark in mesh {
            let point = SIMD2(landmark.x, landmark.y)
            minimum = pointwiseMin(minimum, point)
            maximum = pointwiseMax(maximum, point)
        }
        minimum = simd_clamp(minimum, .zero, .one)
        maximum = simd_clamp(maximum, .zero, .one)
        return CGRect(
            x: CGFloat(minimum.x),
            y: CGFloat(minimum.y),
            width: CGFloat(maximum.x - minimum.x),
            height: CGFloat(maximum.y - minimum.y)
        )
    }

    /// Runs MediaPipe on a square crop centered on `box` and returns the mesh in full-frame
    /// normalized coordinates, or an empty array if no face is found in the crop.
    private func landmarks(around box: CGRect, in pixelBuffer: CVPixelBuffer) -> [SIMD3<Float>] {
        guard let faceLandmarker,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return [] }

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
        let faceSide = max(box.width * CGFloat(frameWidth), box.height * CGFloat(frameHeight))
        let side = min(Int(faceSide * Self.cropScale), frameWidth, frameHeight)
        guard side >= 16 else { return [] }
        // Shift (not shrink) the crop to stay inside the frame so it remains square.
        let originX = min(max(Int(box.midX * CGFloat(frameWidth)) - side / 2, 0), frameWidth - side)
        let originY = min(max(Int(box.midY * CGFloat(frameHeight)) - side / 2, 0), frameHeight - side)

        guard let crop = makeCrop(
            of: pixelBuffer,
            originX: originX,
            originY: originY,
            side: side
        ) else { return [] }

        let result: FaceLandmarkerResult
        do {
            result = try faceLandmarker.detect(image: try MPImage(pixelBuffer: crop))
        } catch {
            print("MediaPipe detection error: \(error.localizedDescription)")
            return []
        }

        // Of the faces found in the crop, keep the one nearest its center (the Vision face).
        let best = result.faceLandmarks
            .map { face -> (face: [NormalizedLandmark], distance: Float) in
                // Mesh index 1 is the nose tip.
                guard face.count > 1 else { return (face, .greatestFiniteMagnitude) }
                let nose = face[1]
                return (face, hypotf(nose.x - 0.5, nose.y - 0.5))
            }
            .min { $0.distance < $1.distance }
        guard let best, best.distance < 0.25 else { return [] }

        let scale = Float(side)
        let width = Float(frameWidth)
        let height = Float(frameHeight)
        let offsetX = Float(originX)
        let offsetY = Float(originY)
        return best.face.map { landmark in
            SIMD3(
                (offsetX + landmark.x * scale) / width,
                (offsetY + landmark.y * scale) / height,
                landmark.z * scale / width
            )
        }
    }

    private func makeCrop(
        of pixelBuffer: CVPixelBuffer,
        originX: Int,
        originY: Int,
        side: Int
    ) -> CVPixelBuffer? {
        guard let cropPool else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, cropPool, &output) == kCVReturnSuccess,
              let output else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        guard let sourceBase = CVPixelBufferGetBaseAddress(pixelBuffer),
              let outputBase = CVPixelBufferGetBaseAddress(output) else { return nil }

        let sourceRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var source = vImage_Buffer(
            data: sourceBase + originY * sourceRowBytes + originX * 4,
            height: vImagePixelCount(side),
            width: vImagePixelCount(side),
            rowBytes: sourceRowBytes
        )
        var destination = vImage_Buffer(
            data: outputBase,
            height: vImagePixelCount(Self.cropSide),
            width: vImagePixelCount(Self.cropSide),
            rowBytes: CVPixelBufferGetBytesPerRow(output)
        )
        // Channel order doesn't matter for scaling, so the ARGB routine handles BGRA as-is.
        let error = vImageScale_ARGB8888(&source, &destination, nil, vImage_Flags(kvImageNoFlags))
        return error == kvImageNoError ? output : nil
    }

    private func makeCropPool() -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Self.cropSide,
            kCVPixelBufferHeightKey as String: Self.cropSide,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        return pool
    }

    // MARK: Tracking

    private func updateTracking(with measurements: [FaceMeasurement], timestamp: Double) -> [FaceTrack] {
        // Greedy assignment over all pairs, closest first, so one face can't steal another's
        // track just because it was detected earlier in the list.
        var candidates: [(track: Int, measurement: Int, distance: CGFloat)] = []
        for trackIndex in trackedFaces.indices {
            let track = trackedFaces[trackIndex].box
            let maxDistance = max(track.width, track.height) * 1.5
            for measurementIndex in measurements.indices {
                let distance = distance(from: track, to: measurements[measurementIndex].box)
                if distance <= maxDistance {
                    candidates.append((trackIndex, measurementIndex, distance))
                }
            }
        }
        candidates.sort { $0.distance < $1.distance }

        var unmatchedTracks = Set(trackedFaces.indices)
        var unmatchedMeasurements = Set(measurements.indices)
        for candidate in candidates
        where unmatchedTracks.contains(candidate.track) && unmatchedMeasurements.contains(candidate.measurement) {
            trackedFaces[candidate.track].update(with: measurements[candidate.measurement], timestamp: timestamp)
            unmatchedTracks.remove(candidate.track)
            unmatchedMeasurements.remove(candidate.measurement)
        }

        for trackIndex in unmatchedTracks {
            trackedFaces[trackIndex].predict(at: timestamp)
        }
        for measurementIndex in unmatchedMeasurements.sorted() {
            trackedFaces.append(
                TrackedFace(id: nextTrackID, measurement: measurements[measurementIndex], timestamp: timestamp)
            )
            nextTrackID += 1
        }
        trackedFaces.removeAll { $0.missedFrames > 2 || $0.box.maxX < 0 || $0.box.minX > 1 ||
            $0.box.maxY < 0 || $0.box.minY > 1 }
        return trackedFaces.map(\.output)
    }

    private func distance(from lhs: CGRect, to rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }

    // MARK: Camera

    private func configureCamera(for device: AVCaptureDevice, fps: Double) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= fps && fps <= $0.maxFrameRate
            }) {
                let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
        } catch {
            print("Camera configuration error: \(error.localizedDescription)")
        }
    }
}

final class CameraController: ObservableObject {
    let captureAspectRatio: CGFloat = 9.0 / 16.0

    enum Status {
        case notDetermined
        case configuring
        case denied
        case unsupported
        case running
    }

    @Published private(set) var status: Status = .notDetermined
    @Published private(set) var faces: [FaceTrack] = []

    // Landmark mode for the whole app. Currently .faceCrops; change to .fullFrame to switch.
    // ASD training extraction must use the same mode (GRAPTION_CONTEXT.md §6).
    private let engine = FaceCaptureEngine(landmarkMode: .faceCrops)
    var session: AVCaptureSession { engine.session }

    init() {
        engine.onFaces = { [weak self] faces in
            DispatchQueue.main.async {
                self?.faces = faces
            }
        }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .configuring
            startEngine()
        case .notDetermined:
            status = .configuring
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startEngine()
                    } else {
                        self?.status = .denied
                    }
                }
            }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    func stop() {
        engine.stop()
        faces = []
    }

    private func startEngine() {
        engine.start { [weak self] success in
            DispatchQueue.main.async {
                self?.status = success ? .running : .unsupported
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

struct CameraView: View {
    @StateObject private var controller = CameraController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.status {
                case .running:
                    GeometryReader { geometry in
                        ZStack {
                            CameraPreview(session: controller.session)
                                .ignoresSafeArea()

                            ForEach(controller.faces) { face in
                                FaceBox(
                                    box: face.box,
                                    hasLandmarks: face.hasLandmarks,
                                    size: geometry.size,
                                    sourceAspectRatio: controller.captureAspectRatio
                                )
                            }

                            Text("Faces: \(controller.faces.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.6), in: Capsule())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                    }
                    .ignoresSafeArea()
                case .notDetermined, .configuring:
                    ProgressView()
                case .denied:
                    statusMessage(
                        "Camera access is off",
                        detail: "Graption needs the camera to see who's speaking. Enable it in Settings.",
                        systemImage: "video.slash"
                    )
                case .unsupported:
                    statusMessage(
                        "Camera unavailable",
                        detail: "This device doesn't have a usable back camera.",
                        systemImage: "exclamationmark.triangle"
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 30, height: 36)
            }
            .padding(.top, 12)
            .padding(.leading, 16)
            .tint(.white)
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    private func statusMessage(_ title: String, detail: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding()
    }
}

/// Solid when MediaPipe fit a mesh to the face; dashed when only Vision detected it
/// (usually a face too small or turned away for landmarks).
private struct FaceBox: View {
    let box: CGRect
    let hasLandmarks: Bool
    let size: CGSize
    let sourceAspectRatio: CGFloat

    var body: some View {
        let scale = max(size.width / sourceAspectRatio, size.height)
        let renderedWidth = sourceAspectRatio * scale
        let renderedHeight = scale
        let horizontalCrop = (renderedWidth - size.width) / 2
        let verticalCrop = (renderedHeight - size.height) / 2

        Rectangle()
            .stroke(.yellow, style: StrokeStyle(lineWidth: 3, dash: hasLandmarks ? [] : [8, 6]))
            .frame(
                width: box.width * renderedWidth,
                height: box.height * renderedHeight
            )
            .position(
                x: box.midX * renderedWidth - horizontalCrop,
                y: box.midY * renderedHeight - verticalCrop
            )
    }
}

#Preview {
    CameraView()
}
