import SwiftUI
import AVFoundation
import GraptionVision
import GraptionCore
import GraptionAudio
import GraptionNetwork
import GraptionUI

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("meetingRetentionDays") private var retentionDays = 0
    @StateObject private var cameraController = CameraController()
    @State private var speakerByCaption: [UUID: String] = [:]
    @State private var captionRecorders: [UUID: SessionRecorder] = [:]
    @State private var toneProbabilities: [UUID: [String: Double]] = [:]
    @State private var toneScores: [UUID: [String: Double]] = [:]
    @State private var sessionStore: FileSessionStore?
    @State private var recorder: SessionRecorder?
    @State private var isSavingCaptions = false
    @State private var persistenceError: String?
    @State private var syncStatus = "Meetings saved locally"
    @State private var meetingSync = MeetingSyncClient()
    @State private var pairedMac = MacPairing.load()
    @State private var pairingRevision = UUID()
    // Demo-first launch: open on the live camera, not Home. Home is still
    // one tap away via the live screen's Home button.
    @State private var showHomeScreen = false
    /// Set when entering the live screen; consumed by the first auto-start so
    /// a manual Stop is never immediately overridden.
    @State private var autoListenArmed = true
    /// Quick start: skip the 3 s room calibration and use a low fixed
    /// threshold (-60 dBFS) so captions begin immediately. Persisted.
    @AppStorage("skipRoomCalibration") private var skipRoomCalibration = true
    @State private var showTranscript = false
    @State private var showSettings = false
    @State private var showSavedSessions = false
    @State private var transcriptReturnsToLive = false
    @State private var capture: MicrophoneCapture?
    @StateObject private var toneMonitor = ToneConnectionMonitor(
        configuration: MacPairing.load()?.toneConfiguration(sessionID: UUID().uuidString)
            ?? ToneClientConfiguration.fromAppConfiguration(sessionID: UUID().uuidString)
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
    @State private var calibrationTask: Task<Bool, Never>?
    @State private var isStarting = false
    @State private var useManualThreshold = false
    @State private var manualThresholdDB: Double?
    @State private var previewCapture: MicrophoneCapture?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewLevel: Float = 0
    @State private var previewError: String?
    @State private var isPreparing = false
    @State private var isReady = false
    @State private var status = "Loading small.en…"
    @State private var setupFailed = false
    @State private var toneVersions: [UUID: String] = [:]
    @State private var toneTags: [UUID: String] = [:]
    @State private var captions: [CaptionEntry] = []
    @State private var listenTask: Task<Void, Never>?

    private var canListen: Bool {
        capture != nil && isReady && !isPreparing && !isCalibrating && !isStarting
            && (isRecording || (pendingCaptions == 0 && !flushingCapture))
    }

    /// Live overlay captions: the latest caption per speaker, drawn over
    /// the camera feed under that speaker's face (see CameraView). Each is
    /// phrase-sized — the last few words — so it fits under a face; the
    /// transcript keeps the full sentences. `captions` is newest-first, so
    /// the first entry seen for a speaker is their latest.
    private var bubbleCaptions: [LiveCaption] {
        var seenSpeakers: Set<String> = []
        return captions.compactMap { entry in
            guard seenSpeakers.insert(entry.speakerID).inserted else { return nil }
            return LiveCaption(id: entry.id, speakerName: speakerLabel(entry.speakerID),
                toneTag: toneTags[entry.id], text: Self.quickCaptionPhrase(entry.text),
                speakerID: entry.speakerID, isPartial: entry.isPartial)
        }
    }

    /// Quick-caption view of an in-progress sentence: the last
    /// `maxWords` words, prefixed with an ellipsis when earlier words
    /// were cut. Keeps the live overlay phrase-sized instead of re-printing
    /// a whole growing sentence.
    static func quickCaptionPhrase(_ text: String, maxWords: Int = 8) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maxWords else { return text }
        return "…" + words.suffix(maxWords).joined(separator: " ")
    }

    private var bannerAlert: GraptionUI.SoundAlert? {
        guard let alert = soundAlertModel.currentAlert else { return nil }
        return GraptionUI.SoundAlert(message: SoundAlertBanner.title(for: alert.label))
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsScreen(
                    cameraPreviewDestination: { AnyView(CameraView(controller: cameraController, captions: bubbleCaptions)) },
                    onBack: {
                        showSettings = false
                        showHomeScreen = true
                    },
                    pairedMacName: pairedMac?.serverURL.host,
                    onPairMac: pairMac,
                    manualThresholdDB: Binding(
                        get: { manualThresholdDB ?? initialManualThresholdDB },
                        set: { manualThresholdDB = $0 }
                    ),
                    manualThresholdEnabled: $useManualThreshold,
                    skipCalibrationEnabled: $skipRoomCalibration,
                    micPreviewActive: previewCapture != nil,
                    micPreviewLevel: Double(previewLevel),
                    micPreviewBreached: previewLevel >= EnergyVAD.rmsThreshold(
                        decibels: manualThresholdDB ?? initialManualThresholdDB
                    ),
                    micPreviewError: previewError,
                    onToggleMicPreview: toggleMicPreview,
                    onStopMicPreview: stopMicPreview
                )
                .onDisappear { stopMicPreview() }
            } else if showTranscript {
                TranscriptScreen(
                    captions: captions.map { entry in
                        TranscriptCaption(
                            id: entry.id,
                            speaker: speakerLabel(entry.speakerID),
                            text: entry.text,
                            tone: toneTags[entry.id], color: colorForSpeaker(entry.speakerID)
                        )
                    },
                    onHome: {
                        showTranscript = false
                        showHomeScreen = !transcriptReturnsToLive
                    }
                )
            } else if showHomeScreen {
                HomeScreen(
                    serverStatus: "\(toneMonitor.state.label) · \(syncStatus)",
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
                    cameraPreviewDestination: { AnyView(CameraView(controller: cameraController, captions: bubbleCaptions)) },
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
                    onSkipCalibration: { calibrationTask?.cancel() },
                    isSettingUp: isPreparing,
                    onHome: {
                        // Leaving live captions turns the microphone off; the
                        // screen-level .onDisappear doesn't fire for in-place swaps.
                        if isRecording || isCalibrating || isStarting { stopListening() }
                        showHomeScreen = true
                    },
                    onTranscript: {
                        transcriptReturnsToLive = true
                        showTranscript = true
                    },
                    onSaveCaptions: {
                        isSavingCaptions = true
                        Task {
                            await saveMeeting()
                            if persistenceError == nil {
                                status = "Captions saved on iPhone — view Saved sessions from Home"
                                AccessibilityNotification.Announcement("Captions saved on iPhone").post()
                            }
                            isSavingCaptions = false
                        }
                    },
                    canSaveCaptions: recorder != nil && !captions.isEmpty
                        && !isStarting && !isCalibrating && !flushingCapture
                        && pendingCaptions == 0 && !isSavingCaptions,
                    pairedMacName: pairedMac?.serverURL.host,
                    onPairMac: pairMac
                )
            } else {
                InstallBaseEnPage(isInstalling: isPreparing, detail: setupFailed ? status : nil) {
                    Task { await prepareModel(allowDownload: true) }
                }
            }
        }
        .sheet(isPresented: $showSavedSessions) {
            SavedSessionsView(activeSessionID: recorder?.hasEnded == false ? recorder?.session.id : nil)
        }
        .alert("Meeting storage", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) { Button("Retry save") { Task { await saveMeeting() } } }
        message: { Text(persistenceError ?? "") }
        .task(id: pairingRevision) {
            do { sessionStore = try FileSessionStore.onDevice() }
            catch { persistenceError = error.localizedDescription }
            startListeningIfNeeded()
            while !Task.isCancelled {
                await syncMeetings()
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startListeningIfNeeded()
            } else if isRecording || isCalibrating {
                // Mic defaults on: resume after backgrounding interrupted it,
                // but not after a manual Stop (autoListenArmed stays false then
                // because stopListening() here is system-initiated).
                autoListenArmed = true
                stopListening()
            }
        }
        .onChange(of: isReady) { _, _ in
            startListeningIfNeeded()
        }
        .onChange(of: showHomeScreen) { _, isHome in
            // Re-entering live captions re-arms the default-on microphone.
            if !isHome {
                autoListenArmed = true
                startListeningIfNeeded()
            }
        }
        .animation(.default, value: soundAlertModel.currentAlert?.id)
        .sensoryFeedback(.warning, trigger: soundAlertModel.currentAlert?.id) { _, new in
            new != nil
        }
        .task {
            isVisible = true
            toneMonitor.onToneDetails = { event in
                guard let captionID = event.captionID, let id = UUID(uuidString: captionID),
                      let owner = captionRecorders.removeValue(forKey: id) else { return }
                // Captions persist on screen, so a late tag simply lands on
                // its caption whenever it arrives; no expiry to defer.
                toneTags[id] = event.tag
                let modelVersion = event.modelVersion ?? "unknown"
                toneVersions[id] = modelVersion
                let probs = event.probs.map {
                    ["anger": $0.anger, "disgust": $0.disgust, "fear": $0.fear,
                     "happy": $0.happy, "neutral": $0.neutral, "sad": $0.sad]
                }
                let scores = event.scores.map {
                    ["arousal": $0.arousal, "valence": $0.valence, "dominance": $0.dominance]
                }
                toneProbabilities[id] = probs
                toneScores[id] = scores
                Task {
                    do {
                        try await owner.applyTone(captionID: id, tag: event.tag,
                            modelVersion: modelVersion, probs: probs, scores: scores)
                        if !owner.hasEnded { try await owner.checkpoint() }
                    } catch { persistenceError = error.localizedDescription }
                }
            }
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
                startListeningIfNeeded()
            } catch {
                report(error)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopMicPreview() }
        }
        .onChange(of: useManualThreshold) { _, enabled in
            if enabled, manualThresholdDB == nil {
                manualThresholdDB = initialManualThresholdDB
            } else if !enabled {
                stopMicPreview()
                previewError = nil
            }
        }
        .onDisappear {
            stopMicPreview()
            if isRecording || isCalibrating { stopListening() }
            isVisible = false
            toneMonitor.stop()
            listenTask?.cancel()
            capture?.onSoundAlert = nil
            capture?.stop()
            soundAlertModel.clear()
            closeASRConnection()
            isRecording = false
            isCalibrating = false
            calibrationCount = nil
        }
    }

    private var initialManualThresholdDB: Double {
        let rms = Double(capture?.automaticThreshold ?? 0.001)
        return min(0, max(-60, (20 * log10(rms)).rounded()))
    }

    private func toggleMicPreview() {
        if previewCapture != nil {
            stopMicPreview()
            return
        }
        guard !isStarting, !isRecording, !isCalibrating else {
            previewError = "Stop listening before previewing the microphone."
            return
        }
        previewError = nil
        let preview = MicrophoneCapture(vad: EnergyVAD(threshold: 0.001))
        previewCapture = preview
        previewTask = Task {
            let granted = await preview.requestPermission()
            guard !Task.isCancelled, previewCapture === preview,
                  showSettings, useManualThreshold, scenePhase != .background else { return }
            guard granted else {
                stopMicPreview()
                previewError = "Microphone permission denied."
                return
            }
            preview.onError = { [weak preview] error in
                guard let preview, previewCapture === preview else { return }
                stopMicPreview()
                previewError = error.localizedDescription
            }
            do {
                try preview.start(previewLevel: { [weak preview] level in
                    guard let preview, previewCapture === preview else { return }
                    previewLevel = level
                })
            } catch {
                stopMicPreview()
                previewError = error.localizedDescription
            }
        }
    }

    private func stopMicPreview() {
        previewTask?.cancel()
        previewTask = nil
        let preview = previewCapture
        previewCapture = nil
        previewLevel = 0
        preview?.stop()
    }

    private func configureCallbacks() {
        guard let capture else { return }
        capture.onSoundAlert = { alert in
            // Calibration measures noise; it must not announce or display alerts.
            guard isRecording, !isCalibrating, isVisible else { return }
            recorder?.appendSound(SavedSoundEvent(id: alert.id, label: alert.label,
                t: alert.t, confidence: alert.confidence, modelVersion: AppleSoundDetector.modelVersion))
            Task { await saveMeeting() }
            soundAlertModel.show(alert)
        }
        capture.onSegment = { segment in
            guard isVisible || flushingCapture else { return }
            pendingCaptions += 1
            speakerByCaption[segment.captionID] = cameraController.speaker(
                from: segment.tStart, to: segment.tEnd)
            if toneMonitor.state == .connected {
                // Retain the owner across the next meeting so a late result reaches its original file.
                captionRecorders[segment.captionID] = recorder
                // Bound unanswered tone requests without retaining audio.
                if captionRecorders.count > 256,
                   let oldest = captionRecorders.keys.first { captionRecorders[oldest] = nil }
            }
            pipeline.enqueue(segment)
            Task {
                await toneMonitor.send(captionID: segment.captionID.uuidString,
                    tStart: segment.tStart, tEnd: segment.tEnd, samples: segment.samples)
            }
        }
        capture.onPartialSegment = { segment in
            // Provisional transcription only; nothing is saved or sent for
            // tone until the final segment lands in onSegment above.
            guard isVisible, isRecording, !isCalibrating else { return }
            pipeline.enqueuePartial(segment)
        }
        capture.onError = { error in
            if isCalibrating {
                isCalibrating = false
                calibrationCount = nil
                calibrationTask?.cancel()
                capture.stop()
            }
            report(error)
        }
        pipeline.onError = { id, error in
            captionFinished()
            report(error, captionID: id)
        }
        pipeline.onPartialResult = { delivery in
            // Live provisional caption: create or update the card for this
            // caption ID in place. The final result (onResult) replaces it.
            // While speaking, only the current phrase is shown — the last
            // few words — like quick live captions; the full sentence
            // arrives with the final.
            let caption = delivery.result
            let fullText = caption.text
                .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayText = Self.quickCaptionPhrase(fullText)
            guard !displayText.isEmpty else { return }
            if let index = captions.firstIndex(where: { $0.id == caption.captionID }) {
                captions[index].text = displayText
                captions[index].isPartial = true
                // Mouth scores build up as the segment grows, so a caption
                // that started "unknown" can earn its speaker on a later
                // partial instead of staying unknown for good.
                let updatedSpeaker = cameraController.speaker(from: caption.tStart, to: caption.tEnd)
                if updatedSpeaker != "unknown" {
                    captions[index].speakerID = updatedSpeaker
                }
            } else {
                captions.insert(CaptionEntry(
                    result: caption,
                    text: displayText,
                    transcriptionSeconds: delivery.transcriptionSeconds,
                    speakerID: cameraController.speaker(from: caption.tStart, to: caption.tEnd),
                    isPartial: true
                ), at: 0)
            }
        }
        pipeline.onResult = { delivery in
            defer { captionFinished() }
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
            guard !isBlankAudio, !isShortEmpty else {
                // A blank final retracts any provisional text it produced.
                captions.removeAll { $0.id == caption.captionID && $0.isPartial }
                return
            }
            // Stable caption IDs keep cards distinct when newer results arrive.
            var entry = CaptionEntry(
                result: caption,
                text: displayText.isEmpty ? "[No speech recognized]" : displayText,
                transcriptionSeconds: delivery.transcriptionSeconds,
                speakerID: speakerByCaption.removeValue(forKey: caption.captionID) ?? "unknown"
            )
            // Replace a provisional caption for this ID in place; the final
            // is saved exactly once, here, never for partials.
            if let index = captions.firstIndex(where: { $0.id == caption.captionID }) {
                entry.speakerID = entry.speakerID == "unknown"
                    ? captions[index].speakerID : entry.speakerID
                captions[index] = entry
            } else {
                captions.insert(entry, at: 0)
            }
            recorder?.append(SavedCaption(id: caption.captionID, text: entry.text,
                speakerID: entry.speakerID, toneTag: toneTags[caption.captionID],
                tStart: caption.tStart, tEnd: caption.tEnd,
                modelVersions: ["asr": caption.asrModelVersion, "asd": MouthMotionScorer.modelVersion].merging(
                    toneVersions[caption.captionID].map { ["tone": $0] } ?? [:]
                ) { _, new in new }, toneProbs: toneProbabilities[caption.captionID],
                toneScores: toneScores[caption.captionID]))
            Task { await saveMeeting() }
        }
    }

    /// Mic defaults on: start listening once the live screen is showing, the
    /// model and capture exist, and the session store is loaded. Consumed on
    /// first use so a manual Stop (or a failed permission prompt) is respected
    /// until the live screen is re-entered.
    private func startListeningIfNeeded() {
        guard autoListenArmed, isVisible, !showHomeScreen, !showSettings, !showTranscript,
              isReady, capture != nil, sessionStore != nil,
              !isRecording, !isCalibrating, !isStarting,
              pendingCaptions == 0, !flushingCapture else { return }
        autoListenArmed = false
        listenTask = Task { await listen() }
    }

    private func prepareModel(allowDownload: Bool) async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        status = "Loading small.en…"
        do {
            try await pipeline.prepare(allowDownload: allowDownload)
            isReady = pipeline.isReady
            setupFailed = !isReady
            status = isReady ? "Ready" : "Could not load small.en"
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
        await saveMeeting()
        guard persistenceError == nil, let sessionStore else { return }
        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }
        guard !Task.isCancelled, isVisible else { return }
        pipeline.reset()
        soundAlertModel.clear()
        captions.removeAll()
        speakerByCaption.removeAll()
        toneProbabilities.removeAll()
        toneScores.removeAll()
        toneVersions.removeAll()
        toneTags.removeAll()
        let manualDB = useManualThreshold ? (manualThresholdDB ?? initialManualThresholdDB) : nil
        // Quick start (default): no 3 s calibration countdown; a low fixed
        // -60 dBFS threshold (the EnergyVAD floor) so speech is picked up
        // immediately. Manual threshold, when enabled, takes precedence.
        let quickStartDB: Double? = manualDB == nil && skipRoomCalibration ? -60 : nil
        capture.setManualThreshold(manualDB ?? quickStartDB)
        if manualDB == nil && quickStartDB == nil {
            do {
                try capture.start(calibrating: true)
            } catch {
                report(error)
                return
            }
            isCalibrating = true
            status = "Keep the room quiet"
            let countdown = Task { @MainActor in
                for count in [3, 2, 1] {
                    guard !Task.isCancelled else { return false }
                    calibrationCount = count
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return false
                    }
                }
                return !Task.isCancelled
            }
            calibrationTask = countdown
            let shouldApplyCalibration = await countdown.value
            calibrationTask = nil
            guard !Task.isCancelled, isVisible, isCalibrating else { return }
            calibrationCount = nil
            isCalibrating = false
            if shouldApplyCalibration {
                do {
                    let threshold = try capture.stopCalibration()
                    logSpeechThreshold(threshold, mode: "Calibrated")
                } catch CalibrationError.tooShort {
                    print("Calibration too short. Using the previous RMS threshold.")
                } catch {
                    capture.stop()
                    report(error)
                    return
                }
            } else {
                capture.stop()
            }
        }
        guard !Task.isCancelled, isVisible else { return }
        do {
            closeASRConnection()
            var transcriber: any CaptionTranscriber = localTranscriber
            let asrConfiguration = pairedMac == nil
                ? ASRClientConfiguration.fromAppConfiguration() : pairedMac?.asrConfiguration
            if let configuration = asrConfiguration {
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
            recorder = SessionRecorder(store: sessionStore)
            let hostTime = mach_absolute_time()
            cameraController.beginMeeting(at: hostTime)
            try capture.start(sessionStartHostTime: hostTime)
            if manualDB != nil {
                logSpeechThreshold(capture.currentThreshold, mode: "Manual")
            } else if quickStartDB != nil {
                logSpeechThreshold(capture.currentThreshold, mode: "Quick start")
            }
            isRecording = true
            status = "Listening"
        } catch {
            cameraController.finishMeeting()
            report(error)
        }
    }

    private func logSpeechThreshold(_ rms: Float, mode: String) {
        #if DEBUG
        let decibels = 20 * log10(Double(rms))
        print(String(format: "%@ RMS threshold: %.6f (%.1f dBFS)", mode, rms, decibels))
        #endif
    }

    private func stopListening() {
        let wasCalibrating = isCalibrating
        isCalibrating = false
        calibrationCount = nil
        isRecording = false
        calibrationTask?.cancel()
        listenTask?.cancel()
        listenTask = nil
        flushingCapture = true
        capture?.stop()
        // Stop enqueues any flushed segment on the main queue before this block.
        DispatchQueue.main.async {
            flushingCapture = false
            if pendingCaptions == 0 {
                closeASRConnection()
                Task { await saveMeeting() }
            }
        }
        soundAlertModel.clear()
        status = wasCalibrating ? "Ready" : "Stopped; finishing pending captions"
    }

    private func captionFinished() {
        pendingCaptions = max(0, pendingCaptions - 1)
        if !isRecording, !flushingCapture, pendingCaptions == 0 {
            closeASRConnection()
            Task { await saveMeeting() }
        }
    }

    private func saveMeeting() async {
        guard let recorder else { return }
        do {
            if !isRecording, !flushingCapture, pendingCaptions == 0 {
                try await recorder.end()
                cameraController.finishMeeting()
                status = "Meeting saved on iPhone"
            } else {
                try await recorder.checkpoint()
            }
            persistenceError = nil
        } catch { persistenceError = "Could not save meeting. \(error.localizedDescription)" }
    }

    private func pairMac(_ code: String) async throws {
        let pairing = try await MacPairing.connect(scannedText: code)
        pairedMac = pairing
        meetingSync = MeetingSyncClient()
        pairingRevision = UUID()
        syncStatus = "Syncing saved meetings"
        toneMonitor.configure(pairing.toneConfiguration(sessionID: UUID().uuidString))
    }

    private func syncMeetings() async {
        guard let sessionStore else { return }
        do {
            if retentionDays > 0 {
                let activeID = recorder?.hasEnded == false ? recorder?.session.id : nil
                let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
                try await sessionStore.prune(olderThan: cutoff, excluding: activeID)
            }
            guard let configuration = pairedMac?.toneConfiguration(sessionID: "meeting-sync")
                ?? ToneClientConfiguration.fromAppConfiguration(sessionID: "meeting-sync")
            else { return }
            try Task.checkCancellation()
            try await meetingSync.sync(store: sessionStore, configuration: configuration)
            try Task.checkCancellation()
            syncStatus = "Saved meetings synced"
        } catch {
            if !Task.isCancelled { syncStatus = "Meetings saved locally; sync will retry" }
        }
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
            Color.graptionBackground
                .ignoresSafeArea()
            VStack(spacing: 20) {
                GraptionLogo()
                    .frame(width: 88, height: 88)
                    .padding(.bottom, 8)
                Text("Install small.en")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.graptionAccent)
                Text("Wi-Fi is needed")
                    .font(.title3)
                    .foregroundStyle(Color.graptionSecondaryText)
                if let detail, detail != "Wi-Fi is needed" {
                    Text(detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.graptionAccent.opacity(0.8))
                }
                Button {
                    install()
                } label: {
                    Text(isInstalling ? "Installing…" : "Install")
                        .foregroundStyle(Color.graptionBackground)
                }
                .disabled(isInstalling)
                .buttonStyle(.borderedProminent)
                .tint(Color.graptionPeach)
            }
            .padding(32)
        }
    }
}

/// Presentation data only; the transcription/event contracts are unchanged.
private struct CaptionEntry: Identifiable {
    var result: TranscriptionResult
    var text: String
    var transcriptionSeconds: TimeInterval
    var speakerID: String
    /// Provisional (still-being-spoken) text; the final result clears this.
    var isPartial: Bool = false
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
