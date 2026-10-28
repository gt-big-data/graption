//
//  ContentView.swift
//  Graption
//
//  Created by Akshaj Nadimpalli on 9/29/26.
//

import SwiftUI
import Foundation
import GraptionNetwork

struct ContentView: View {
    @State private var showCamera = false
    @StateObject private var toneMonitor = ToneConnectionMonitor(
        configuration: ToneClientConfiguration.fromAppConfiguration(
            sessionID: UUID().uuidString
        )
    )

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Text(toneMonitor.state.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showCamera = true
            } label: {
                Label("Open Camera", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .fullScreenCover(isPresented: $showCamera) {
            CameraView()
        }
        .task {
            toneMonitor.start()
        }
    }
}

#Preview {
    ContentView()
}
