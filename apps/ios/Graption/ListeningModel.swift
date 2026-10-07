//
//  ListeningModel.swift
//  Graption
//
//  Created by Arjun on 10/6/26.
//

import GraptionAudio
import Observation
import SwiftUI

// Wires mic capture to the UI. Temporary until GraptionCore
// owns the session and GraptionUI owns the alert banner.
@MainActor
@Observable
final class ListeningModel {
    private(set) var isListening = false
    private(set) var currentAlert: SoundAlert?
    private(set) var errorMessage: String?

    private var capture: MicrophoneCapture?
    private var hasPrintedLabels = false

    func toggle() async {
        if isListening {
            stop()
        } else {
            await start()
        }
    }

    private func start() async {
        do {
            printKnownLabelsOnce()

            let capture = MicrophoneCapture(
                // Placeholder; tune on a real phone.
                vad: EnergyVAD(threshold: 0.01),
                soundDetector: try AppleSoundDetector()
            )

            capture.onSegment = { segment in
                print(String(
                    format: "Segment %.2f–%.2f s",
                    segment.tStart,
                    segment.tEnd
                ))
            }
            capture.onSoundAlert = { [weak self] alert in
                self?.show(alert)
            }
            capture.onError = { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }

            guard await capture.requestPermission() else {
                errorMessage = "Turn on microphone access in Settings."
                return
            }

            try capture.start()
            self.capture = capture
            isListening = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stop() {
        capture?.stop()
        capture = nil
        isListening = false
    }

    private func show(_ alert: SoundAlert) {
        print(String(
            format: "Sound %@ at %.2f s (%.2f)",
            alert.label,
            alert.t,
            alert.confidence
        ))

        currentAlert = alert
        AccessibilityNotification.Announcement(
            SoundAlertBanner.title(for: alert.label)
        ).post()

        Task {
            try? await Task.sleep(for: .seconds(4))
            if currentAlert?.id == alert.id {
                currentAlert = nil
            }
        }
    }

    private func printKnownLabelsOnce() {
        guard !hasPrintedLabels,
              let labels = try? AppleSoundDetector.knownClassifications()
        else {
            return
        }

        hasPrintedLabels = true
        print("SoundAnalysis knows \(labels.count) sounds:")
        print(labels.joined(separator: "\n"))
    }
}
