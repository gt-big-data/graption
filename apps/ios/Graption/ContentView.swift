//
//  ContentView.swift
//  Graption
//
//  Created by Akshaj Nadimpalli on 9/29/26.
//

import SwiftUI
import GraptionUI

struct ContentView: View {
    var body: some View {
        LiveCaptionScreen(cameraPreviewDestination: { AnyView(CameraView()) })
    }
}

#Preview {
    ContentView()
}
