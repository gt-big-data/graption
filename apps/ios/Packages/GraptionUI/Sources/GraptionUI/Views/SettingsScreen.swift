import AVFoundation
import SwiftUI
import VisionKit

public struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("toneTagsEnabled") private var toneTagsEnabled: Bool = true
    @State private var showCameraPreview = false
    @State private var showPairingScanner = false
    @State private var isPairing = false
    @State private var pairingMessage: String?
    private let cameraPreviewDestination: (() -> AnyView)?
    private let onBack: (() -> Void)?
    private let pairedMacName: String?
    private let onPairMac: ((String) async throws -> Void)?

    private let manualThresholdDB: Binding<Double>?
    private let manualThresholdEnabled: Binding<Bool>
    private let skipCalibrationEnabled: Binding<Bool>
    private let micPreviewActive: Bool
    private let micPreviewLevel: Double
    private let micPreviewBreached: Bool
    private let micPreviewError: String?
    private let onToggleMicPreview: () -> Void
    private let onStopMicPreview: () -> Void

    public init(
        cameraPreviewDestination: (() -> AnyView)? = nil,
        onBack: (() -> Void)? = nil,
        pairedMacName: String? = nil,
        onPairMac: ((String) async throws -> Void)? = nil,
        manualThresholdDB: Binding<Double>? = nil,
        manualThresholdEnabled: Binding<Bool> = .constant(false),
        skipCalibrationEnabled: Binding<Bool> = .constant(true),
        micPreviewActive: Bool = false,
        micPreviewLevel: Double = 0,
        micPreviewBreached: Bool = false,
        micPreviewError: String? = nil,
        onToggleMicPreview: @escaping () -> Void = {},
        onStopMicPreview: @escaping () -> Void = {}
    ) {
        self.cameraPreviewDestination = cameraPreviewDestination
        self.onBack = onBack
        self.pairedMacName = pairedMacName
        self.onPairMac = onPairMac
        self.manualThresholdDB = manualThresholdDB
        self.manualThresholdEnabled = manualThresholdEnabled
        self.skipCalibrationEnabled = skipCalibrationEnabled
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
        .sheet(isPresented: $showPairingScanner) {
            NavigationStack {
                PairingScanner(onScan: { code in
                    showPairingScanner = false
                    Task { await pairMac(code) }
                }, onFailure: {
                    showPairingScanner = false
                    pairingMessage = "The camera could not start scanning."
                })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan pairing code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showPairingScanner = false }
                    }
                }
            }
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
            Text("Mac Server")
                .font(.title3.bold())
                .foregroundStyle(Color.graptionAccent)

            Text(pairedMacName.map { "Paired with \($0)" } ?? "Open the Graption dashboard on your Mac and choose Pair an iPhone or iPad.")
                .font(.footnote)
                .foregroundStyle(Color.graptionSecondaryText)

            if onPairMac != nil {
                Button {
                    Task {
                        guard DataScannerViewController.isSupported else {
                            pairingMessage = "This device does not support QR scanning."
                            return
                        }
                        guard await AVCaptureDevice.requestAccess(for: .video),
                              DataScannerViewController.isAvailable else {
                            pairingMessage = "Allow camera access in Settings to scan the pairing code."
                            return
                        }
                        pairingMessage = nil
                        showPairingScanner = true
                    }
                } label: {
                    Label(isPairing ? "Connecting…" : "Scan pairing code", systemImage: "qrcode.viewfinder")
                        .font(.body.bold())
                        .foregroundStyle(Color.graptionBackground)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.graptionAccent, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isPairing)
            }

            if let pairingMessage {
                Text(pairingMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
            }
        }
    }

    private func pairMac(_ code: String) async {
        guard let onPairMac else { return }
        isPairing = true
        defer { isPairing = false }
        do {
            try await onPairMac(code)
            pairingMessage = "Mac connection saved."
        } catch {
            pairingMessage = error.localizedDescription
        }
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

            Toggle("Quick start (skip calibration)", isOn: skipCalibrationEnabled)
                .tint(Color.graptionAccent)

            Text("Captions start immediately with a low fixed speech threshold "
                + "(−60 dB), instead of the 3-second room calibration. Best for "
                + "demos and quiet rooms; in noisy rooms it may caption extra "
                + "sounds. Turn off to measure the room each time you listen.")
                .font(.footnote)
                .foregroundStyle(Color.graptionSecondaryText)

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
                Text("Saved on this device")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.graptionAccent)
                Text("Your Mac pairing and tone tag preference stay saved when you reopen Graption.")
                    .font(.footnote)
                    .foregroundStyle(Color.graptionSecondaryText)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
    }
}

private struct PairingScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            recognizesMultipleItems: false
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            Task { @MainActor in onFailure() }
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var didScan = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ scanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didScan, case .barcode(let barcode)? = addedItems.first,
                  let code = barcode.payloadStringValue else { return }
            didScan = true
            scanner.stopScanning()
            onScan(code)
        }
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
