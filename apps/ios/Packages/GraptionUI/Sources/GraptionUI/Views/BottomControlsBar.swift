import SwiftUI

struct BottomControlsBar: View {
    var isListening = true
    var onToggleMic: () -> Void = {}
    var onTranscript: () -> Void = {}
    var onRecalibrate: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleMic) {
                Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isListening ? Color.graptionAccent : Color.graptionSecondaryText)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.graptionAccent, lineWidth: 1))
            }
            .accessibilityLabel(isListening ? "Pause captions" : "Resume captions")

            Button(action: onTranscript) {
                HStack(spacing: 8) {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 20))
                    Text("Transcript")
                        .font(.body.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(Color.graptionAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.graptionAccent, lineWidth: 1))
            }
            .accessibilityLabel("Transcript")

            Button(action: onRecalibrate) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.graptionAccent)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.graptionAccent, lineWidth: 1))
            }
            .accessibilityLabel("Recalibrate room noise")
            .accessibilityHint("Stay quiet for a few seconds while Graption measures background noise.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.graptionAccent).frame(height: 1)
        }
    }
}

#Preview {
    BottomControlsBar()
        .background(Color.graptionBackground)
}
