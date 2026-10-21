import Foundation
import GraptionAudio
import GraptionCore
import GraptionUI
import Observation

/// Owns the shared microphone, the caption pipeline, and the saved-session recorder
/// for the live-captions screen. Everything here runs on-device.
///
/// Startup: load WhisperKit base.en (downloading it once if this phone has never
/// had it), measure room noise for a moment, then listen. Pausing saves the session.
@MainActor
@Observable
final class LiveSession {
    /// Shown as "Someone" until speaker fusion exists (GRAPTION_CONTEXT.md §6, Fusion).
    private static let unknownSpeaker = "Someone"
    private static let calibrationSeconds = 2.5

    private(set) var captions: [LiveCaption] = []
    private(set) var status = "Starting…"
    private(set) var isListening = false
    let soundAlerts = SoundAlertModel()

    var soundAlert: GraptionUI.SoundAlert? {
        soundAlerts.currentAlert.map {
            GraptionUI.SoundAlert(message: "\(SoundAlertBanner.title(for: $0.label)) detected")
        }
    }

    /// Changes once per new alert, for haptics.
    var soundAlertID: UUID? { soundAlerts.currentAlert?.id }

    private let pipeline = CaptionPipeline()
    private let store = try? FileSessionStore.onDevice()
    private var capture: MicrophoneCapture?
    private var recorder: SessionRecorder?
    /// The paused session, kept until its last flushed segment is transcribed.
    private var finishingRecorder: SessionRecorder?
    private var hasStarted = false
    private var isBusy = false
    private var isCalibrating = false
    private var resumeWhenActive = false
    /// Set once Pause's flushed segment has reached the pipeline.
    private var isFinishingSession = false

    init() {
        pipeline.onResult = { [weak self] delivery in self?.handle(delivery) }
        pipeline.onError = { [weak self] id, error in self?.report(error, captionID: id) }
        pipeline.onIdle = { [weak self] in
            guard let self, isFinishingSession else { return }
            finishSession()
        }
    }

    // MARK: Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isBusy = true
        defer { isBusy = false }

        guard await prepareModel() else { return }

        let capture: MicrophoneCapture
        do {
            capture = MicrophoneCapture(
                vad: EnergyVAD(threshold: 0.001),
                soundDetector: try AppleSoundDetector()
            )
        } catch {
            report(error)
            return
        }
        capture.onSegment = { [weak self] segment in self?.pipeline.enqueue(segment) }
        capture.onSoundAlert = { [weak self] alert in
            // Calibration measures noise; it must not announce or display alerts.
            guard let self, isListening, !isCalibrating else { return }
            soundAlerts.show(alert)
        }
        capture.onError = { [weak self] error in self?.report(error) }
        self.capture = capture

        guard await capture.requestPermission() else {
            status = "Microphone access is off. Turn it on in Settings › Graption."
            return
        }
        await calibrate()
        beginListening()
    }

    func toggleListening() {
        guard !isBusy else { return }
        if capture == nil {
            // Setup failed (e.g. no internet for the first model download); try again.
            hasStarted = false
            Task { await start() }
        } else if isListening {
            pause()
        } else {
            beginListening()
        }
    }

    func recalibrate() {
        guard !isBusy, capture != nil else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            let wasListening = isListening
            if wasListening { pause() }
            await calibrate()
            if wasListening { beginListening() }
        }
    }

    /// iOS stops the audio engine in the background, so pause there and resume on return.
    func sceneDidEnterBackground() {
        resumeWhenActive = isListening
        if isListening { pause() }
    }

    func sceneDidBecomeActive() {
        guard resumeWhenActive else { return }
        resumeWhenActive = false
        beginListening()
    }

    // MARK: Steps

    private func prepareModel() async -> Bool {
        do {
            status = "Loading speech model…"
            try await pipeline.prepare(allowDownload: false)
            return true
        } catch TranscriberError.modelNotProvisioned {
            // First run on this phone: fetch base.en once, then it works offline.
            status = "Downloading speech model (first run only, needs internet)…"
            do {
                try await pipeline.prepare(allowDownload: true)
                return true
            } catch {
                report(error)
                return false
            }
        } catch {
            report(error)
            return false
        }
    }

    private func calibrate() async {
        guard let capture else { return }
        do {
            try capture.start(calibrating: true)
            isCalibrating = true
            status = "Measuring room noise. Stay quiet for a moment…"
            try? await Task.sleep(for: .seconds(Self.calibrationSeconds))
            isCalibrating = false
            let threshold = try capture.stopCalibration()
            print(String(format: "Calibrated RMS threshold: %.6f", threshold))
        } catch {
            isCalibrating = false
            capture.stop()
            report(error)
        }
    }

    private func beginListening() {
        guard let capture, !isListening else { return }
        // Resumed before the previous session's last caption arrived; save what it has.
        finishSession()
        pipeline.reset()
        soundAlerts.clear()
        captions.removeAll()
        recorder = store.map { SessionRecorder(store: $0) }
        do {
            try capture.start()
            isListening = true
            status = "Listening"
        } catch {
            recorder = nil
            report(error)
        }
    }

    private func pause() {
        guard isListening else { return }
        isListening = false
        capture?.stop()
        finishingRecorder = recorder
        recorder = nil
        soundAlerts.clear()
        status = "Paused. Tap the mic to resume."
        // Stopping flushes the unfinished segment onto the main queue; this block runs
        // after it is enqueued, so the pipeline's idle callback fires after its result.
        DispatchQueue.main.async { [self] in
            guard finishingRecorder != nil else { return }
            isFinishingSession = true
            if !pipeline.hasPendingWork { finishSession() }
        }
    }

    private func finishSession() {
        isFinishingSession = false
        guard let recorder = finishingRecorder else { return }
        finishingRecorder = nil
        guard !recorder.session.captions.isEmpty else { return }
        Task { await save(recorder) }
    }

    private func save(_ recorder: SessionRecorder) async {
        do {
            try await recorder.end()
            print("Saved session \(recorder.session.id) with \(recorder.session.captions.count) captions")
        } catch {
            report(error)
        }
    }

    // MARK: Results

    private func handle(_ delivery: CaptionPipeline.Delivery) {
        let caption = delivery.result
        print(String(
            format: "Caption %@ [%@] %.2f–%.2f s (ASR %.2f s): %@",
            caption.captionID.uuidString, caption.asrModelVersion,
            caption.tStart, caption.tEnd, delivery.transcriptionSeconds, caption.text
        ))
        let text = Self.displayText(caption.text)
        guard !text.isEmpty else { return }

        captions.append(LiveCaption(id: caption.captionID, speakerName: Self.unknownSpeaker, text: text))
        (recorder ?? finishingRecorder)?.append(SavedCaption(
            id: caption.captionID,
            text: text,
            speakerID: "unknown",
            tStart: max(0, caption.tStart),
            tEnd: max(0, caption.tEnd),
            modelVersions: ["asr": caption.asrModelVersion]
        ))
    }

    /// Whisper marks non-speech as bracketed or parenthesized tags ("[BLANK_AUDIO]",
    /// "(wind blowing)"). Hide those in presentation; the raw text stays in the log.
    static func displayText(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func report(_ error: Error, captionID: UUID? = nil) {
        status = error.localizedDescription
        print("Caption/capture error [\(captionID?.uuidString ?? "setup")]: \(error.localizedDescription)")
    }
}
