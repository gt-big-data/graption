import SwiftUI

/// U3: Connection & Preferences. Collects and persists the Mac tone-server
/// address and the tone-tags toggle locally on the phone. No networking or
/// server discovery happens here — that's wired up separately once the
/// tone client exists.
public struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("macServerAddress") private var savedServerAddress: String = ""
    @AppStorage("toneTagsEnabled") private var toneTagsEnabled: Bool = true

    @State private var addressDraft: String = ""
    @State private var isAddressSaved: Bool = false
    @FocusState private var isAddressFieldFocused: Bool

    @State private var showCameraPreview = false
    private let cameraPreviewDestination: (() -> AnyView)?
    private let onBack: (() -> Void)?

    private let manualThresholdDB: Binding<Double>?
    private let manualThresholdEnabled: Binding<Bool>
    private let micPreviewActive: Bool
    private let micPreviewLevel: Double
    private let micPreviewBreached: Bool
    private let micPreviewError: String?
    private let onToggleMicPreview: () -> Void
    private let onStopMicPreview: () -> Void

    public init(
        cameraPreviewDestination: (() -> AnyView)? = nil,
        onBack: (() -> Void)? = nil,
        manualThresholdDB: Binding<Double>? = nil,
        manualThresholdEnabled: Binding<Bool> = .constant(false),
        micPreviewActive: Bool = false,
        micPreviewLevel: Double = 0,
        micPreviewBreached: Bool = false,
        micPreviewError: String? = nil,
        onToggleMicPreview: @escaping () -> Void = {},
        onStopMicPreview: @escaping () -> Void = {}
    ) {
        self.cameraPreviewDestination = cameraPreviewDestination
        self.onBack = onBack
        self.manualThresholdDB = manualThresholdDB
        self.manualThresholdEnabled = manualThresholdEnabled
        self.micPreviewActive = micPreviewActive
        self.micPreviewLevel = micPreviewLevel
        self.micPreviewBreached = micPreviewBreached
        self.micPreviewError = micPreviewError
        self.onToggleMicPreview = onToggleMicPreview
        self.onStopMicPreview = onStopMicPreview
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    macServerCard
                    accessibilityCard
                    if let manualThresholdDB {
                        speechDetectionCard(threshold: manualThresholdDB)
                    }
                    if cameraPreviewDestination != nil {
                        cameraPreviewRow
                    }
                    storageFootnote
                }
                .padding(16)
            }
        }
        .background(Color.graptionBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            addressDraft = savedServerAddress
            isAddressSaved = !savedServerAddress.isEmpty
        }
        .fullScreenCover(isPresented: $showCameraPreview) {
            if let cameraPreviewDestination {
                cameraPreviewDestination()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CircleIconButton(systemName: "chevron.left", accessibilityLabel: "Back to live captions") {
                if let onBack {
                    onBack()
                } else {
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Connection & Preferences")
                    .font(.headline.bold())
                    .foregroundStyle(Color.graptionAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Graption • Settings")
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.graptionBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.graptionAccent).frame(height: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var macServerCard: some View {
        SettingsCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Mac Server")
                    .font(.title3.bold())
                    .foregroundStyle(Color.graptionAccent)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.graptionSecondaryText)
                        .frame(width: 6, height: 6)
                    Text("Not connected.")
                        .font(.caption)
                        .foregroundStyle(Color.graptionSecondaryText)
                }
                .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Server Address")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.graptionAccent)

                TextField(
                    "",
                    text: $addressDraft,
                    prompt: Text("e.g., 192.168.1.100:8080").foregroundStyle(Color.graptionSecondaryText)
                )
                .foregroundStyle(Color.graptionSecondaryText)
                .font(.callout)
                .focused($isAddressFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.graptionAccent, lineWidth: 1))
                .onChange(of: addressDraft) { _, newValue in
                    // Fires for the onAppear restore too, not just user edits,
                    // so compare against the persisted value instead of
                    // unconditionally clearing the "saved" state.
                    isAddressSaved = (newValue == savedServerAddress)
                }

                Text("Enter the address of the Mac you want to connect to.")
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
            }

            Button {
                isAddressFieldFocused = false
                savedServerAddress = addressDraft
                isAddressSaved = true
            } label: {
                Text("Save Address")
                    .font(.body.bold())
                    .foregroundStyle(Color.graptionBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.graptionAccent, in: RoundedRectangle(cornerRadius: 14))
            }

            if isAddressSaved {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.graptionAccent)
                    Text("Address saved.")
                        .font(.footnote.bold())
                        .foregroundStyle(Color.graptionAccent)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isAddressSaved)
    }

    private var accessibilityCard: some View {
        SettingsCard {
            Text("Accessibility Preferences")
                .font(.title3.bold())
                .foregroundStyle(Color.graptionAccent)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Show Tone Tags")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.graptionAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Spacer(minLength: 8)

                    Toggle("Show Tone Tags", isOn: $toneTagsEnabled)
                        .labelsHidden()
                        .tint(Color.graptionAccent)
                }

                Text("Display tone indicators such as [sarcastic], [joking], or [serious] alongside captions.")
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
            }

            Text("Changes apply immediately and save automatically on this iPhone.")
                .font(.footnote)
                .foregroundStyle(Color.graptionSecondaryText)
        }
    }

    private func speechDetectionCard(threshold: Binding<Double>) -> some View {
        SettingsCard {
            Text("Speech Detection")
                .font(.title3.bold())
                .foregroundStyle(Color.graptionAccent)

            Toggle("Manual threshold", isOn: manualThresholdEnabled)
                .tint(Color.graptionAccent)

            if manualThresholdEnabled.wrappedValue {
                let decibels = threshold.wrappedValue
                let value = "\(Int(decibels)) dBFS"
                Slider(value: threshold, in: -60...0, step: 1) {
                    Text("Speech threshold")
                }
                .tint(Color.graptionAccent)
                .accessibilityValue(Text(value))
                Text("Threshold: \(value)")
                    .font(.footnote)

                if micPreviewActive {
                    micMeter(thresholdDB: decibels)
                }

                Button(micPreviewActive ? "Stop preview" : "Preview mic", action: onToggleMicPreview)
                    .tint(Color.graptionAccent)

                if let micPreviewError {
                    Text(micPreviewError)
                        .font(.footnote)
                }

                Text("Applies the next time you tap Listen.")
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
            }
        }
    }

    private func micMeter(thresholdDB: Double) -> some View {
        let levelDB = 20 * log10(micPreviewLevel)
        let fill = min(1, max(0, (levelDB + 60) / 60))
        let marker = (thresholdDB + 60) / 60

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.graptionSecondaryText.opacity(0.25))
                    Capsule().fill(Color.graptionAccent)
                        .frame(width: geometry.size.width * fill)
                    Rectangle().fill(.primary)
                        .frame(width: 2)
                        .offset(x: max(0, geometry.size.width - 2) * marker)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            Text(micPreviewBreached ? "Above threshold" : "Below threshold")
                .font(.footnote)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(micPreviewBreached ? "Above threshold" : "Below threshold")
    }

    // Dev/debug entry point to the raw AVFoundation camera preview (not part
    // of the Figma design); only shown when the app target injects one.
    private var cameraPreviewRow: some View {
        Button {
            onStopMicPreview()
            showCameraPreview = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.graptionAccent)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())

                Text("Preview Camera")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.graptionAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.graptionSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview Camera")
    }

    private var storageFootnote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 18))
                .foregroundStyle(Color.graptionAccent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Saved on this iPhone")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.graptionAccent)
                Text("Your server address and tone tag preference stay saved when you reopen Graption. No account or cloud sync needed.")
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}

#Preview("Accessibility XXXL") {
    NavigationStack {
        SettingsScreen()
    }
    .dynamicTypeSize(.accessibility5)
}
