import SwiftUI

/// U1: the live-captions screen. The app target owns the real camera, audio, and
/// session state and passes them in; `SimulatedLiveCaptionScreen` drives the same
/// screen from a scripted fake session for previews.
public struct LiveCaptionScreen<Feed: View>: View {
    private let captions: [LiveCaption]
    private let soundAlert: SoundAlert?
    private let status: String
    private let isListening: Bool
    private let onToggleListening: () -> Void
    private let onRecalibrate: () -> Void
    private let settingsDestinations: [SettingsDestination]
    private let feed: Feed

    @State private var showSettings = false
    @State private var showTranscript = false

    public init(
        captions: [LiveCaption],
        soundAlert: SoundAlert?,
        status: String,
        isListening: Bool,
        onToggleListening: @escaping () -> Void = {},
        onRecalibrate: @escaping () -> Void = {},
        settingsDestinations: [SettingsDestination] = [],
        @ViewBuilder feed: () -> Feed
    ) {
        self.captions = captions
        self.soundAlert = soundAlert
        self.status = status
        self.isListening = isListening
        self.onToggleListening = onToggleListening
        self.onRecalibrate = onRecalibrate
        self.settingsDestinations = settingsDestinations
        self.feed = feed()
    }

    public var body: some View {
        NavigationStack {
            screenContent
                .navigationDestination(isPresented: $showSettings) {
                    SettingsScreen(destinations: settingsDestinations)
                }
        }
    }

    private var screenContent: some View {
        VStack(spacing: 0) {
            CaptionHeaderView(subtitle: status, onSettings: { showSettings = true })
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            if let soundAlert {
                SoundAlertBannerView(alert: soundAlert)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            LiveVideoFeedView(captions: captions) { feed }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomControlsBar(
                isListening: isListening,
                onToggleMic: onToggleListening,
                onTranscript: { showTranscript = true },
                onRecalibrate: onRecalibrate
            )
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .background(Color.graptionBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeOut(duration: 0.3), value: soundAlert)
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(captions: captions)
        }
    }
}

/// The live-captions screen over the placeholder image, driven by the scripted
/// `LiveCaptionSessionSimulator`. For previews and UI work without a phone.
public struct SimulatedLiveCaptionScreen: View {
    @State private var simulator = LiveCaptionSessionSimulator()

    public init() {}

    public var body: some View {
        LiveCaptionScreen(
            captions: simulator.captions,
            soundAlert: simulator.soundAlert,
            status: "Graption • Simulated session",
            isListening: true
        ) {
            Image("LiveVideoPlaceholder", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .task { simulator.start() }
        .onDisappear { simulator.stop() }
    }
}

#Preview {
    SimulatedLiveCaptionScreen()
}

#Preview("Accessibility XXXL") {
    SimulatedLiveCaptionScreen()
        .dynamicTypeSize(.accessibility5)
}
