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

final class CameraController: NSObject, ObservableObject {
    enum Status {
        case notDetermined
        case configuring
        case denied
        case unsupported
        case running
    }

    @Published private(set) var status: Status = .notDetermined

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.graption.camera.session")

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

            self.configureFrameRate(for: device, fps: 15)

            self.session.commitConfiguration()

            self.session.startRunning()
            DispatchQueue.main.async { self.status = .running }
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
                    CameraPreview(session: controller.session).ignoresSafeArea()
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

#Preview {
    CameraView()
}
