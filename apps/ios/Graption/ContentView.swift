import SwiftUI
import GraptionAudio

@MainActor
struct ContentView: View {
    @State private var capture: MicrophoneCapture?
    @State private var soundAlertModel = SoundAlertModel()
    @State private var hasPrintedLabels = false
    @State private var isVisible = false
    @State private var pipeline = CaptionPipeline()
    @State private var isRecording = false
    @State private var isCalibrating = false
    @State private var isStarting = false
    @State private var threshold: Float = 0.001
    @State private var isPreparing = false
    @State private var isReady = false
    @State private var status = "Set up the model before recording"
    @State private var captions: [CaptionEntry] = []

    var body: some View {
        VStack(spacing: 12) {
            Text(status)
            if !isReady {
                Button("Set up base.en (first time needs internet)") {
                    Task { await prepareModel(allowDownload: true) }
                }
                .disabled(isPreparing)
            }
            Text(String(format: "Noise threshold: %.4f", threshold))
                .font(.caption)
            Text("Calibrate with at least 2 seconds of room noise, without speaking.")
                .font(.caption)
            Button {
                if isCalibrating {
                    finishCalibration()
                } else {
                    Task { await startCalibration() }
                }
            } label: {
                Label(
                    isCalibrating ? "Stop calibration" : "Calibrate room noise",
                    systemImage: isCalibrating ? "stop.fill" : "waveform"
                )
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(capture == nil || isRecording || isStarting || isPreparing)

            Button {
                if isRecording {
                    stopCapture()
                } else {
                    Task { await startCapture() }
                }
            } label: {
                Label(
                    isRecording ? "Stop listening" : "Start listening",
                    systemImage: isRecording ? "stop.fill" : "mic.fill"
                )
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(capture == nil || !isReady || isPreparing || isCalibrating || isStarting)

            if let alert = soundAlertModel.currentAlert {
                SoundAlertBanner(alert: alert)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if captions.isEmpty {
                        Text("No captions yet")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(captions) { caption in
                        CaptionCard(caption: caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .animation(.default, value: soundAlertModel.currentAlert?.id)
        .sensoryFeedback(.warning, trigger: soundAlertModel.currentAlert?.id) { _, new in
            new != nil
        }
        .task {
            isVisible = true
            do {
                // Reuse one capture so calibration survives Stop/Start.
                if capture == nil {
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
            capture?.onSegment = nil
            capture?.onSoundAlert = nil
            capture?.stop()
            soundAlertModel.clear()
            pipeline.reset()
            isRecording = false
            isCalibrating = false
        }
    }

    private func configureCallbacks() {
        guard let capture else { return }
        capture.onSoundAlert = { alert in
            // Calibration measures noise; it must not announce or display alerts.
            guard isRecording, !isCalibrating, isVisible else { return }
            soundAlertModel.show(alert)
        }
        capture.onSegment = { segment in pipeline.enqueue(segment) }
        capture.onError = { error in
            if isCalibrating {
                capture.stop()
                isCalibrating = false
            }
            report(error)
        }
        pipeline.onError = { id, error in
            report(error, captionID: id)
        }
        pipeline.onResult = { delivery in
            let caption = delivery.result
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
            captions.insert(CaptionEntry(
                result: caption,
                text: displayText.isEmpty ? "[No speech recognized]" : displayText,
                transcriptionSeconds: delivery.transcriptionSeconds
            ), at: 0)
        }
    }

    private func prepareModel(allowDownload: Bool) async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        status = allowDownload ? "Setting up base.en…" : "Loading local base.en…"
        do {
            try await pipeline.prepare(allowDownload: allowDownload)
            isReady = pipeline.isReady
            status = "Ready"
        } catch {
            report(error)
        }
    }

    private func startCalibration() async {
        guard let capture else { return }
        guard !isRecording, !isCalibrating, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
        guard !Task.isCancelled, isVisible else { return }
        pipeline.reset()
        soundAlertModel.clear()
        do {
            try capture.start(calibrating: true)
            isCalibrating = true
            status = "Calibrating room noise… do not speak"
        } catch {
            report(error)
        }
    }

    private func finishCalibration() {
        guard let capture else { return }
        isCalibrating = false
        do {
            threshold = try capture.stopCalibration()
            status = "Calibration complete"
            print(String(format: "Calibrated RMS threshold: %.6f", threshold))
        } catch {
            report(error)
        }
    }

    private func startCapture() async {
        guard let capture else { return }
        guard !isRecording, !isCalibrating, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        pipeline.reset()
        soundAlertModel.clear()
        captions.removeAll()
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
        guard !Task.isCancelled, isVisible else { return }
        do {
            try capture.start()
            isRecording = true
            status = "Listening"
        } catch {
            report(error)
        }
    }

    private func stopCapture() {
        // Normal Stop lets the final flushed segment finish transcription.
        isRecording = false
        capture?.stop()
        soundAlertModel.clear()
        status = "Stopped; finishing pending captions"
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


/// Presentation data only; the transcription/event contracts are unchanged.
private struct CaptionEntry: Identifiable {
    let result: TranscriptionResult
    let text: String
    let transcriptionSeconds: TimeInterval
    var id: UUID { result.captionID }
}

private struct CaptionCard: View {
    let caption: CaptionEntry
    // Every row uses the same time-column width, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var timeColumnWidth: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "%.2f s", caption.result.tStart))
                Text(String(format: "%.2f s", caption.result.tEnd))
            }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: timeColumnWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(caption.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                Text(String(format: "Transcription latency: %.2f s", caption.transcriptionSeconds))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
