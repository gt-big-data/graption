import SwiftUI

/// Live captions screen. Pass `onMicrophone` to drive it from the real
/// microphone pipeline. With no handler, previews keep the scripted session.
public struct LiveCaptionScreen: View {
    @State private var simulator = LiveCaptionSessionSimulator()
    @State private var showSettings = false
    @State private var showControlsMenu = false

    private let cameraPreviewDestination: (() -> AnyView)?
    private let suppliedCaptions: [LiveCaption]?
    private let suppliedAlert: SoundAlert?
    private let isListening: Bool
    private let canListen: Bool
    private let statusText: String?
    private let onMicrophone: (() -> Void)?
    private let onSetup: (() -> Void)?
    private let setupTitle: String
    private let onCalibrate: (() -> Void)?
    private let isCalibrating: Bool
    private let calibrationCount: Int?
    private let isSettingUp: Bool
    private let onHome: (() -> Void)?

    public init(
        cameraPreviewDestination: (() -> AnyView)? = nil,
        captions: [LiveCaption]? = nil,
        soundAlert: SoundAlert? = nil,
        isListening: Bool = false,
        canListen: Bool = true,
        statusText: String? = nil,
        onMicrophone: (() -> Void)? = nil,
        onSetup: (() -> Void)? = nil,
        setupTitle: String = "Set up captions",
        onCalibrate: (() -> Void)? = nil,
        isCalibrating: Bool = false,
        calibrationCount: Int? = nil,
        isSettingUp: Bool = false,
        onHome: (() -> Void)? = nil
    ) {
        self.cameraPreviewDestination = cameraPreviewDestination
        self.suppliedCaptions = captions
        self.suppliedAlert = soundAlert
        self.isListening = isListening
        self.canListen = canListen
        self.statusText = statusText
        self.onMicrophone = onMicrophone
        self.onSetup = onSetup
        self.setupTitle = setupTitle
        self.onCalibrate = onCalibrate
        self.isCalibrating = isCalibrating
        self.calibrationCount = calibrationCount
        self.isSettingUp = isSettingUp
        self.onHome = onHome
    }

    private var usesLiveAudio: Bool { onMicrophone != nil }

    private var displayedCaptions: [LiveCaption] {
        suppliedCaptions ?? simulator.captions
    }

    private var displayedAlert: SoundAlert? {
        usesLiveAudio ? suppliedAlert : simulator.soundAlert
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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if let alert = displayedAlert {
                    SoundAlertBannerView(alert: alert)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                videoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if onSetup != nil || onCalibrate != nil {
                    preparationRow
                }
            }
            .background(Color.graptionBackground.ignoresSafeArea())

            // Floating menu button
            Button(action: { showControlsMenu = true }) {
                ZStack {
                    Circle()
                        .fill(Color.graptionAccent)

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.graptionBackground)
                }
                .frame(width: 56, height: 56)
            }
            .padding(16)

            // Calibration overlay
            if let calibrationCount {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 8) {
                        Text("Calibrating")
                            .font(.title2.bold())
                            .foregroundStyle(Color.graptionAccent)
                        Text("\(calibrationCount)")
                            .font(.system(size: 120, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("Keep the room quiet")
                            .font(.title3.bold())
                            .foregroundStyle(Color.graptionAccent)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Calibrating. Keep the room quiet. \(calibrationCount)")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeOut(duration: 0.2), value: calibrationCount)
        .animation(.easeOut(duration: 0.3), value: displayedAlert?.message)
        .sheet(isPresented: $showControlsMenu) {
            controlsMenu
        }
        .task {
            guard !usesLiveAudio else { return }
            simulator.start()
        }
        .onDisappear {
            simulator.stop()
        }
    }

    private var videoArea: some View {
        ZStack(alignment: .bottom) {
            if let dest = cameraPreviewDestination {
                dest()
            } else {
                LiveVideoFeedView(captions: displayedCaptions)
            }

            if !displayedCaptions.isEmpty && cameraPreviewDestination != nil {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displayedCaptions) { caption in
                        CaptionBubbleView(caption: caption)
                    }
                }
                .padding(12)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var preparationRow: some View {
        HStack(spacing: 12) {
            if let onSetup {
                Button(setupTitle, action: onSetup)
                    .disabled(isSettingUp)
            }
            if let onCalibrate {
                Button(isCalibrating ? "Stop calibration" : "Calibrate room noise", action: onCalibrate)
                    .disabled(isSettingUp)
            }
        }
        .font(.footnote.bold())
        .foregroundStyle(Color.graptionAccent)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.graptionBackground)
    }

    private var controlsMenu: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Controls")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.graptionAccent)

                Spacer()

                Button(action: { showControlsMenu = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.graptionAccent)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 0) {
                    // Transcript
                    Button(action: { showControlsMenu = false }) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 18))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transcript")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Text-only view")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.graptionSecondaryText)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.graptionSecondaryText)
                        }
                        .foregroundStyle(Color.graptionAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)

                    // Microphone
                    Button(action: { onMicrophone?() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Microphone")
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            Spacer()

                            Text(isListening ? "On" : "Off")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.graptionSecondaryText)
                        }
                        .foregroundStyle(Color.graptionAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)

                    // Settings
                    Button(action: {
                        showControlsMenu = false
                        showSettings = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "gear")
                                .font(.system(size: 18))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connection & Preferences")
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.graptionSecondaryText)
                        }
                        .foregroundStyle(Color.graptionAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)

                    // Home
                    Button(action: {
                        showControlsMenu = false
                        onHome?()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 18))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Back to Home")
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.graptionSecondaryText)
                        }
                        .foregroundStyle(Color.graptionAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .background(Color.graptionBackground.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationCornerRadius(20)
    }
}

#Preview {
    LiveCaptionScreen()
}

#Preview("Accessibility XXXL") {
    LiveCaptionScreen()
        .dynamicTypeSize(.accessibility5)
}
