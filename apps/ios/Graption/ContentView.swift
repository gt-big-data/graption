import SwiftUI
import GraptionAudio
import GraptionNetwork
import GraptionUI

@MainActor
struct ContentView: View {
    @State private var showHomeScreen = true
    @State private var showTranscript = false
    @State private var showSettings = false
    @State private var showSavedSessions = false
    @State private var transcriptReturnsToLive = false
    @State private var capture: MicrophoneCapture?
    @StateObject private var toneMonitor = ToneConnectionMonitor(
        configuration: ToneClientConfiguration.fromAppConfiguration(
            sessionID: UUID().uuidString
        )
    )
    @State private var soundAlertModel = SoundAlertModel()
    @State private var hasPrintedLabels = false
    @State private var isVisible = false
    @State private var pipeline = CaptionPipeline()
    @State private var localTranscriber = WhisperKitTranscriber()
    @State private var asrClient: ASRClient?
    @State private var pendingCaptions = 0
    @State private var flushingCapture = false
    @State private var isRecording = false
    @State private var isCalibrating = false
    @State private var calibrationCount: Int?
    @State private var isStarting = false
    @State private var threshold: Float = 0.001
    @State private var isPreparing = false
    @State private var isReady = false
    @State private var status = "Loading base.en…"
    @State private var setupFailed = false
    @State private var captions: [CaptionEntry] = []
    /// Captions whose on-screen time is up. They leave the camera view but stay in the transcript.
    @State private var expiredCaptionIDs: Set<UUID> = []
    @State private var listenTask: Task<Void, Never>?

    private var canListen: Bool {
        capture != nil && isReady && !isPreparing && !isCalibrating && !isStarting
            && (isRecording || (pendingCaptions == 0 && !flushingCapture))
    }

    /// At most three unexpired captions, oldest first, matching the three-bubble layout.
    private var bubbleCaptions: [LiveCaption] {
        Array(captions.filter { !expiredCaptionIDs.contains($0.id) }.prefix(3))
            .reversed()
            .map { entry in
                LiveCaption(id: entry.id, speakerName: "Someone", text: entry.text)
            }
    }

    /// How long a caption stays over the camera: reading time at 3 words per second
    /// (180 wpm, the upper end of broadcast subtitle guidance), held for 3 to 7 seconds.
    /// 7 s is the common per-subtitle maximum (e.g. Netflix, BBC).
    static func onScreenSeconds(for text: String) -> Double {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return min(7, max(3, Double(words) / 3))
    }

    private func scheduleExpiry(of entry: CaptionEntry) {
        let id = entry.id
        let seconds = Self.onScreenSeconds(for: entry.text)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            expiredCaptionIDs.insert(id)
        }
    }

    private var bannerAlert: GraptionUI.SoundAlert? {
        guard let alert = soundAlertModel.currentAlert else { return nil }
        return GraptionUI.SoundAlert(message: SoundAlertBanner.title(for: alert.label))
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsScreen(
                    cameraPreviewDestination: { AnyView(CameraView(captions: bubbleCaptions)) },
                    onBack: {
                        showSettings = false
                        showHomeScreen = true
                    }
                )
            } else if showTranscript {
                TranscriptScreen(
                    captions: captions.map { entry in
                        TranscriptCaption(
                            id: entry.id,
                            speaker: "Someone",
                            text: entry.text,
                            tone: nil
                        )
                    },
                    onHome: {
                        showTranscript = false
                        showHomeScreen = !transcriptReturnsToLive
                    }
                )
            } else if showHomeScreen {
                HomeScreen(
                    serverStatus: toneMonitor.state.label,
                    onOpenLiveCaptions: {
                        showHomeScreen = false
                    },
                    onOpenSettings: {
                        showSettings = true
                        showHomeScreen = false
                    },
                    onOpenTranscript: {
                        transcriptReturnsToLive = false
                        showTranscript = true
                        showHomeScreen = false
                    },
                    onOpenSavedSessions: {
                        showSavedSessions = true
                    }
                )
            } else if isReady {
                LiveCaptionScreen(
                    cameraPreviewDestination: { AnyView(CameraView(captions: bubbleCaptions)) },
                    captions: bubbleCaptions,
                    soundAlert: bannerAlert,
                    isListening: isRecording || isCalibrating,
                    canListen: canListen,
                    statusText: "\(status) · \(toneMonitor.state.label)",
                    onMicrophone: {
                        if isRecording || isCalibrating {
                            stopListening()
                        } else {
                            listenTask = Task { await listen() }
                        }
                    },
                    calibrationCount: calibrationCount,
                    isSettingUp: isPreparing,
                    onHome: {
                        // Leaving live captions turns the microphone off; the
                        // screen-level .onDisappear doesn't fire for in-place swaps.
                        if isRecording || isCalibrating { stopListening() }
                        showHomeScreen = true
                    },
                    onTranscript: {
                        transcriptReturnsToLive = true
                        showTranscript = true
                    }
                )
            } else {
                InstallBaseEnPage(isInstalling: isPreparing, detail: setupFailed ? status : nil) {
                    Task { await prepareModel(allowDownload: true) }
                }
            }
        }
        .sheet(isPresented: $showSavedSessions) {
            SavedSessionsView()
        }
        .animation(.default, value: soundAlertModel.currentAlert?.id)
        .sensoryFeedback(.warning, trigger: soundAlertModel.currentAlert?.id) { _, new in
            new != nil
        }
        .task {
            isVisible = true
            toneMonitor.start()
            do {
                // Reuse one capture so calibration survives Stop/Start.
                if capture == nil {
                    pipeline = CaptionPipeline(transcriber: localTranscriber)
                    capture = MicrophoneCapture(
                        vad: EnergyVAD(threshold: 0.001),
                        soundDetector: try AppleSoundDetector()
                    )
                }
                printKnownLabelsOnce()
                configureCallbacks()
                await prepareModel(allowDownload: false)
            } catch {
                report(error)
            }
        }
        .onDisappear {
            isVisible = false
            toneMonitor.stop()
            listenTask?.cancel()
            capture?.onSegment = nil
            capture?.onSoundAlert = nil
            capture?.stop()
            soundAlertModel.clear()
            pipeline.reset()
            closeASRConnection()
            pendingCaptions = 0
            isRecording = false
            isCalibrating = false
            calibrationCount = nil
        }
    }

    private func configureCallbacks() {
        guard let capture else { return }
        capture.onSoundAlert = { alert in
            // Calibration measures noise; it must not announce or display alerts.
            guard isRecording, !isCalibrating, isVisible else { return }
            soundAlertModel.show(alert)
        }
        capture.onSegment = { segment in
            guard isVisible else { return }
            pendingCaptions += 1
            pipeline.enqueue(segment)
        }
        capture.onError = { error in
            if isCalibrating {
                capture.stop()
                isCalibrating = false
            }
            report(error)
        }
        pipeline.onError = { id, error in
            captionFinished()
            report(error, captionID: id)
        }
        pipeline.onResult = { delivery in
            captionFinished()
            let caption = delivery.result
            if isRecording, asrClient != nil {
                status = caption.asrModelVersion.hasPrefix("mlx-whisper-")
                    ? "Listening — Mac captions" : "Listening — iPhone captions"
            }
            // Retained for later queue/UI diagnostics: measures enqueue-to-callback
            // time, including queue wait and ASR, but not the actual visible frame.
            // let delay = CaptionPipeline.seconds(delivery.receivedAt.duration(to: .now))
            // let line = String(
            //     format: "%.2f–%.2f s: %@\nTranscription time: %.2f s · Total processing time: %.2f s\n",
            //     caption.tStart, caption.tEnd,
            //     caption.text.isEmpty ? "[No speech recognized]" : caption.text,
            //     delivery.transcriptionSeconds, delay
            // )
            let line = String(
                format: "%.2f–%.2f s: %@\nSpeech-to-text (ASR) transcription time: %.2f s\n",
                caption.tStart, caption.tEnd,
                caption.text.isEmpty ? "[No speech recognized]" : caption.text,
                delivery.transcriptionSeconds
            )
            // Log every result, including short noise-triggered empty transcriptions.
            print("Caption \(caption.captionID) [\(caption.asrModelVersion)] \(line)")
            // Whisper may emit a blank-audio marker; hide it only in presentation.
            let displayText = caption.text
                .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isBlankAudio = caption.text.contains("[BLANK_AUDIO]") && displayText.isEmpty
            let isShortEmpty = caption.tEnd - caption.tStart < 1 && displayText.isEmpty
            guard !isBlankAudio, !isShortEmpty else { return }
            // Stable caption IDs keep cards distinct when newer results arrive.
            let entry = CaptionEntry(
                result: caption,
                text: displayText.isEmpty ? "[No speech recognized]" : displayText,
                transcriptionSeconds: delivery.transcriptionSeconds
            )
            captions.insert(entry, at: 0)
            scheduleExpiry(of: entry)
        }
    }

    private func prepareModel(allowDownload: Bool) async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        status = "Loading base.en…"
        do {
            try await pipeline.prepare(allowDownload: allowDownload)
            isReady = pipeline.isReady
            setupFailed = !isReady
            status = isReady ? "Ready" : "Could not load base.en"
        } catch {
            let missing = (error as? TranscriberError) == .modelNotProvisioned
            setupFailed = allowDownload || !missing
            if missing, !allowDownload {
                status = "Wi-Fi is needed"
            } else {
                report(error)
            }
        }
    }

    /// Quiet stretch before captions. The detector needs 2 seconds of audio;
    /// 3 seconds leaves room for the microphone to start.
    private func listen() async {
        guard let capture else { return }
        guard canListen, !isRecording else { return }
        isStarting = true
        defer { isStarting = false }
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
        guard !Task.isCancelled, isVisible else { return }
        pipeline.reset()
        soundAlertModel.clear()
        captions.removeAll()
        expiredCaptionIDs.removeAll()
        do {
            try capture.start(calibrating: true)
        } catch {
            report(error)
            return
        }
        isCalibrating = true
        status = "Keep the room quiet"
        for count in [3, 2, 1] {
            guard !Task.isCancelled, isVisible, isCalibrating else { return }
            calibrationCount = count
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
        guard !Task.isCancelled, isVisible, isCalibrating else { return }
        calibrationCount = nil
        isCalibrating = false
        do {
            threshold = try capture.stopCalibration()
            print(String(format: "Calibrated RMS threshold: %.6f", threshold))
        } catch {
            capture.stop()
            report(error)
            return
        }
        guard !Task.isCancelled, isVisible else { return }
        do {
            closeASRConnection()
            var transcriber: any CaptionTranscriber = localTranscriber
            if let configuration = ASRClientConfiguration.fromAppConfiguration() {
                let client = ASRClient(configuration: configuration)
                asrClient = client
                transcriber = FallbackCaptionTranscriber(
                    remote: MacCaptionTranscriber(client: client), local: localTranscriber
                )
            }
            pipeline = CaptionPipeline(transcriber: transcriber)
            configureCallbacks()
            try await pipeline.prepare(allowDownload: false)
            try Task.checkCancellation()
            guard isVisible else { return }
            try capture.start()
            isRecording = true
            status = "Listening"
        } catch {
            report(error)
        }
    }

    private func stopListening() {
        let wasCalibrating = isCalibrating
        isCalibrating = false
        calibrationCount = nil
        isRecording = false
        listenTask?.cancel()
        listenTask = nil
        flushingCapture = true
        capture?.stop()
        // Stop enqueues any flushed segment on the main queue before this block.
        DispatchQueue.main.async {
            flushingCapture = false
            if pendingCaptions == 0 { closeASRConnection() }
        }
        soundAlertModel.clear()
        status = wasCalibrating ? "Ready" : "Stopped; finishing pending captions"
    }

    private func captionFinished() {
        pendingCaptions = max(0, pendingCaptions - 1)
        if !isRecording, !flushingCapture, pendingCaptions == 0 { closeASRConnection() }
    }

    private func closeASRConnection() {
        guard let client = asrClient else { return }
        asrClient = nil
        Task { await client.disconnect() }
    }

    private func printKnownLabelsOnce() {
        guard !hasPrintedLabels,
              let labels = try? AppleSoundDetector.knownClassifications() else { return }
        hasPrintedLabels = true
        print("SoundAnalysis knows \(labels.count) sounds:")
        print(labels.joined(separator: "\n"))
    }

    private func report(_ error: Error, captionID: UUID? = nil) {
        status = error.localizedDescription
        print("Caption/capture error [\(captionID?.uuidString ?? "setup")]: \(error.localizedDescription)")
    }
}


private struct InstallBaseEnPage: View {
    var isInstalling: Bool
    var detail: String?
    var install: () -> Void

    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 31 / 255, blue: 59 / 255)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Install base.en")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color(red: 1, green: 149 / 255, blue: 0))
                Text("Wi-Fi is needed")
                    .font(.title3)
                    .foregroundStyle(.white)
                if let detail, detail != "Wi-Fi is needed" {
                    Text(detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Button(isInstalling ? "Installing…" : "Install") {
                    install()
                }
                .disabled(isInstalling)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1, green: 149 / 255, blue: 0))
            }
            .padding(32)
        }
    }
}

/// Presentation data only; the transcription/event contracts are unchanged.
private struct CaptionEntry: Identifiable {
    let result: TranscriptionResult
    let text: String
    let transcriptionSeconds: TimeInterval
    var id: UUID { result.captionID }
}


/// Bridges the network package to the audio package without coupling their APIs.
private struct MacCaptionTranscriber: CaptionTranscriber {
    let client: ASRClient

    func prepare(allowDownload: Bool) async throws {}

    func transcribe(_ segment: AudioSegment) async throws -> TranscriptionResult {
        let reply = try await client.transcribe(captionID: segment.captionID,
            tStart: segment.tStart, tEnd: segment.tEnd, samples: segment.samples)
        return TranscriptionResult(captionID: segment.captionID, text: reply.text,
            tStart: segment.tStart, tEnd: segment.tEnd, asrModelVersion: reply.modelVersion)
    }
}
