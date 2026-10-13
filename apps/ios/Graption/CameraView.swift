//
//  CameraView.swift
//  Graption
//
//  Created by Arya Vaidya on 9/30/26.
//

import SwiftUI
import AVFoundation
import Combine
import UIKit
import MediaPipeTasksVision

final class CameraController: NSObject, ObservableObject, FaceLandmarkerLiveStreamDelegate {
    enum Status {
        case notDetermined
        case configuring
        case denied
        case unsupported
        case running
    }

    @Published private(set) var status: Status = .notDetermined
    @Published private(set) var faceBoxes: [CGRect] = []
    @Published private(set) var detectedFaceCount = 0

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.graption.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var faceLandmarker: FaceLandmarker?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .configuring
            configureAndStart()
        case .notDetermined:
            status = .configuring
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStart()
                } else {
                    DispatchQueue.main.async { self.status = .denied }
                }
            }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func faceLandmarker(
        _ faceLandmarker: FaceLandmarker,
        didFinishDetection result: FaceLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        guard error == nil, let result else {
            if let error {
                print("MediaPipe detection error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.faceBoxes = []
                self?.detectedFaceCount = 0
            }
            return
        }

        let boxes: [CGRect] = result.faceLandmarks.compactMap { landmarks in
            let xs = landmarks.map { CGFloat($0.x) }
            let ys = landmarks.map { CGFloat($0.y) }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else {
                return nil
            }
            return CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.faceBoxes = boxes
            self?.detectedFaceCount = boxes.count
        }
    }

    // Back camera, 720p, 15 fps
    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { self.status = .unsupported }
                return
            }

            self.session.beginConfiguration()

            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            }

            guard self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = .unsupported }
                return
            }
            self.session.addInput(input)

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = .unsupported }
                return
            }
            self.session.addOutput(self.videoOutput)

            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }

            guard let modelPath = Bundle.main.path(
                forResource: "face_landmarker",
                ofType: "task"
            ) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = .unsupported }
                return
            }

            do {
                let options = FaceLandmarkerOptions()
                options.baseOptions.modelAssetPath = modelPath
                options.runningMode = .liveStream
                options.numFaces = 4
                options.outputFaceBlendshapes = true
                options.outputFacialTransformationMatrixes = true
                options.faceLandmarkerLiveStreamDelegate = self
                self.faceLandmarker = try FaceLandmarker(options: options)
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = .unsupported }
                return
            }

            self.configureFrameRate(for: device, fps: 15)

            self.session.commitConfiguration()

            self.session.startRunning()
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func process(_ sampleBuffer: CMSampleBuffer) {
        guard let faceLandmarker else { return }

        do {
            let image = try MPImage(sampleBuffer: sampleBuffer)
            let timestamp = Int(
                CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000
            )
            try faceLandmarker.detectAsync(
                image: image,
                timestampInMilliseconds: timestamp
            )
        } catch {
            print("MediaPipe frame error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.faceBoxes = []
                self?.detectedFaceCount = 0
            }
        }
    }

    private func configureFrameRate(for device: AVCaptureDevice, fps: Double) {
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= fps && fps <= $0.maxFrameRate
        }) else { return }

        do {
            try device.lockForConfiguration()
            let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            // Frame rate could not be configured --> Use default
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        process(sampleBuffer)
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

                            ForEach(Array(controller.faceBoxes.enumerated()), id: \.offset) { _, box in
                                FaceBox(box: box, size: geometry.size)
                            }

                            Text("Faces: \(controller.detectedFaceCount)")
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

private struct FaceBox: View {
    let box: CGRect
    let size: CGSize

    var body: some View {
        Rectangle()
            .stroke(.yellow, lineWidth: 3)
            .frame(
                width: box.width * size.width,
                height: box.height * size.height
            )
            .position(
                x: box.midX * size.width,
                y: box.midY * size.height
            )
    }
}

#Preview {
    CameraView()
}
