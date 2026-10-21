//
//  ContentView.swift
//  Graption
//
//  Created by Akshaj Nadimpalli on 9/29/26.
//

import SwiftUI
import GraptionUI

/// Wiring only: the camera feed with face tracking (Vision + MediaPipe), live captions
/// and sound alerts (GraptionAudio), saved sessions (GraptionCore), all shown in the
/// GraptionUI live-captions screen.
struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var session = LiveSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LiveCaptionScreen(
            captions: session.captions,
            soundAlert: session.soundAlert,
            status: session.status,
            isListening: session.isListening,
            onToggleListening: session.toggleListening,
            onRecalibrate: session.recalibrate,
            settingsDestinations: [
                SettingsDestination(title: "Saved Sessions", systemImage: "clock.arrow.circlepath") {
                    AnyView(SavedSessionsView())
                }
            ]
        ) {
            CameraFeedView(controller: camera)
                .onAppear { camera.start() }
                .onDisappear { camera.stop() }
        }
        .sensoryFeedback(.warning, trigger: session.soundAlertID) { _, new in
            new != nil
        }
        .task { await session.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.sceneDidEnterBackground()
            case .active: session.sceneDidBecomeActive()
            default: break
            }
        }
    }
}

#Preview {
    ContentView()
}
