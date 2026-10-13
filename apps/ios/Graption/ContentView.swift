//
//  ContentView.swift
//  Graption
//
//  Created by Akshaj Nadimpalli on 9/29/26.
//

import SwiftUI

struct ContentView: View {
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

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
    }
}

#Preview {
    ContentView()
}
