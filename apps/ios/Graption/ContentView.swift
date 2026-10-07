//
//  ContentView.swift
//  Graption
//
//  Created by Akshaj Nadimpalli on 9/29/26.
//

import GraptionAudio
import SwiftUI

struct ContentView: View {
    @State private var model = ListeningModel()

    var body: some View {
        VStack(spacing: 24) {
            if let alert = model.currentAlert {
                SoundAlertBanner(alert: alert)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            Button {
                Task { await model.toggle() }
            } label: {
                Label(
                    model.isListening ? "Stop listening" : "Start listening",
                    systemImage: model.isListening ? "stop.fill" : "mic.fill"
                )
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
        .animation(.default, value: model.currentAlert?.id)
        .sensoryFeedback(.warning, trigger: model.currentAlert?.id) { _, new in
            new != nil
        }
    }
}

#Preview {
    ContentView()
}
