import SwiftUI
import GraptionAudio

@MainActor
struct ContentView: View {
    @State private var capture = MicrophoneCapture(vad: EnergyVAD(threshold: 0.001))
    @State private var pipeline = CaptionPipeline()
    @State private var isRecording = false
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
            .disabled(!isReady || isPreparing)

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
        }
    }

    private func configureCallbacks() {
        capture.onSegment = { segment in pipeline.enqueue(segment) }
        capture.onError = { error in report(error) }
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
            results += line + "\n"
            // This marks the state update, not the exact frame becoming visible.
            print("Caption \(caption.captionID) [\(caption.asrModelVersion)] \(line)")
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

    private func startCapture() async {
        pipeline.reset()
        results = ""
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
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
