//
//  ContentView.swift
//  Graption
//
//  Created by Akshaj Nadimpalli on 9/29/26.
//
import SwiftUI
import GraptionAudio

@MainActor
struct ContentView: View {
    @State private var capture = MicrophoneCapture(
        vad: EnergyVAD(threshold: 0.001)
    )

    @State private var isRecording = false
    @State private var status = "Ready"
    @State private var results = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(status)

            Button(isRecording ? "Stop" : "Start") {
                if isRecording {
                    capture.stop()
                    isRecording = false
                    status = "Stopped"
                } else {
                    Task {
                        await startCapture()
                    }
                }
            }

            ScrollView {
                Text(results.isEmpty ? "No segments yet" : results)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .onDisappear {
            capture.stop()
            isRecording = false
        }
    }

    private func startCapture() async {
        capture.onSegment = { segment in
            let line = String(
                format: "%.2f–%.2f seconds",
                segment.tStart,
                segment.tEnd
            )

            print(line)                // Xcode console
            results += line + "\n"     // Phone screen
        }

        capture.onError = { error in
            status = error.localizedDescription
            print("Capture error: \(error)")
        }

        guard await capture.requestPermission() else {
            status = "Microphone permission denied"
            return
        }

        do {
            try capture.start()
            isRecording = true
            status = "Listening"
        } catch {
            status = error.localizedDescription
        }
    }
}
