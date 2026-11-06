import SwiftUI

/// Live captions screen. Pass `onMicrophone` to drive it from the real
/// microphone pipeline. With no handler, previews keep the scripted session.
public struct LiveCaptionScreen: View {
    @State private var simulator = LiveCaptionSessionSimulator()
    @State private var showSettings = false
    @State private var showControlsMenu = false
    @State private var pendingMenuAction: MenuAction?

    private enum MenuAction {
        case transcript, microphone, settings, home
    }

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
    private let onTranscript: (() -> Void)?

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
        onHome: (() -> Void)? = nil,
        onTranscript: (() -> Void)? = nil
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
        self.onTranscript = onTranscript
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
        ZStack(alignment: .topLeading) {
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
                        .fill(Color.graptionBackground)
                    Circle()
                        .stroke(Color.graptionAccent, lineWidth: 1)

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.graptionAccent)
                }
                .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Controls")
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
        // Screen changes wait for the sheet to finish closing; swapping views
        // while it is still presented drops the navigation.
        .sheet(isPresented: $showControlsMenu, onDismiss: runPendingMenuAction) {
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
                            .transition(.opacity)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.3), value: displayedCaptions.map(\.id))
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

            VStack(spacing: 0) {
                menuRow(icon: "doc.text", title: "Transcript", subtitle: "Text-only view") {
                    choose(.transcript)
                }
                menuDivider
                microphoneRow
                menuDivider
                menuRow(icon: "gear", title: "Connection & Preferences") {
                    choose(.settings)
                }
                menuDivider
                menuRow(icon: "house.fill", title: "Back to Home") {
                    choose(.home)
                }
            }

            Spacer(minLength: 0)
        }
        .background(Color.graptionBackground.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationCornerRadius(20)
    }

    private var microphoneRow: some View {
        HStack(spacing: 12) {
            Image(systemName: isListening ? "mic.fill" : "mic.slash")
                .font(.system(size: 18))
                .frame(width: 24)

            Text("Microphone")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Text(isListening ? "On" : "Off")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.graptionSecondaryText)

            Toggle("Microphone", isOn: Binding(
                get: { isListening },
                set: { turnOn in
                    // Turning on starts a calibration countdown, so close the
                    // menu first to keep the countdown visible.
                    if turnOn { choose(.microphone) } else { onMicrophone?() }
                }
            ))
            .labelsHidden()
            .tint(Color.graptionAccent)
            .disabled(!isListening && !canListen)
        }
        .foregroundStyle(Color.graptionAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var menuDivider: some View {
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.horizontal, 16)
    }

    private func menuRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.graptionSecondaryText)
                    }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ action: MenuAction) {
        pendingMenuAction = action
        showControlsMenu = false
    }

    private func runPendingMenuAction() {
        guard let action = pendingMenuAction else { return }
        pendingMenuAction = nil
        switch action {
        case .transcript: onTranscript?()
        case .microphone: onMicrophone?()
        case .settings: showSettings = true
        case .home: onHome?()
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
