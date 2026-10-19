import SwiftUI

/// U1: the live-captions screen, driven by a scripted fake session until the
/// real vision/audio/fusion pipeline (P1) is ready to supply real captions,
/// tone tags, and sound alerts.
public struct LiveCaptionScreen: View {
    @State private var simulator = LiveCaptionSessionSimulator()
    @State private var showSettings = false

    private let cameraPreviewDestination: (() -> AnyView)?

    public init(cameraPreviewDestination: (() -> AnyView)? = nil) {
        self.cameraPreviewDestination = cameraPreviewDestination
    }

    public var body: some View {
        NavigationStack {
            screenContent
                .navigationDestination(isPresented: $showSettings) {
                    SettingsScreen(cameraPreviewDestination: cameraPreviewDestination)
                }
        }
    }

    private var screenContent: some View {
        VStack(spacing: 0) {
            CaptionHeaderView(onSettings: { showSettings = true })
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            if let alert = simulator.soundAlert {
                SoundAlertBannerView(alert: alert)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            LiveVideoFeedView(captions: simulator.captions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomControlsBar()
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .background(Color.graptionBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeOut(duration: 0.3), value: simulator.soundAlert)
        .task {
            simulator.start()
        }
        .onDisappear {
            simulator.stop()
        }
    }
}

#Preview {
    LiveCaptionScreen()
}

#Preview("Accessibility XXXL") {
    LiveCaptionScreen()
        .dynamicTypeSize(.accessibility5)
}
