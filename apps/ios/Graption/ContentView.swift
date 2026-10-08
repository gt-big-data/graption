import SwiftUI
import GraptionAudio

@MainActor
struct ContentView: View {
    @State private var capture = MicrophoneCapture(vad: EnergyVAD(threshold: 0.001))
    @State private var pipeline = CaptionPipeline()
    @State private var isRecording = false
    @State private var isCalibrating = false
    @State private var isStarting = false
    @State private var threshold: Float = 0.001
    @State private var isPreparing = false
    @State private var isReady = false
    @State private var status = "Set up the model before recording"
    @State private var results = ""

    var body: some View {
        VStack(spacing: 16) {
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
            Button(isCalibrating ? "Stop calibration" : "Start calibration") {
                if isCalibrating {
                    finishCalibration()
                } else {
                    Task { await startCalibration() }
                }
            }
            .disabled(isRecording || isStarting || isPreparing)
            Button(isRecording ? "Stop" : "Start") {
                if isRecording {
                    // Normal Stop lets the final flushed segment finish transcription.
                    capture.stop()
                    isRecording = false
                    status = "Stopped; finishing pending captions"
                } else {
                    Task { await startCapture() }
                }
            }
            .disabled(!isReady || isPreparing || isCalibrating || isStarting)

            ScrollView {
                Text(results.isEmpty ? "No captions yet" : results)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .task {
            configureCallbacks()
            await prepareModel(allowDownload: false)
        }
        .onDisappear {
            capture.onSegment = nil
            capture.stop()
            pipeline.reset()
            isRecording = false
            isCalibrating = false
        }
    }

    private func configureCallbacks() {
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
            let isShortEmpty = caption.tEnd - caption.tStart < 1
                && caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard !isShortEmpty else { return }
            // Display newest completed captions first; transcription remains FIFO.
            results = line + "\n" + results
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
        guard !isRecording, !isCalibrating, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
        guard !Task.isCancelled else { return }
        pipeline.reset()
        do {
            try capture.start(calibrating: true)
            isCalibrating = true
            status = "Calibrating room noise… do not speak"
        } catch {
            report(error)
        }
    }

    private func finishCalibration() {
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
        guard !isRecording, !isCalibrating, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        pipeline.reset()
        results = ""
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
        guard !Task.isCancelled else { return }
        do {
            try capture.start()
            isRecording = true
            status = "Listening"
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error, captionID: UUID? = nil) {
        status = error.localizedDescription
        print("Caption/capture error [\(captionID?.uuidString ?? "setup")]: \(error.localizedDescription)")
    }
}
