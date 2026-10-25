import SwiftUI

struct BottomControlsBar: View {
    var isListening = false
    var canListen = true
    var onMicrophone: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onMicrophone) {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.graptionAccent)
                    .frame(width: 56, height: 56)
                    .background(
                        isListening ? Color.graptionAccent.opacity(0.35) : Color.white.opacity(0.08),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(Color.graptionAccent, lineWidth: 1))
            }
            .disabled(!canListen && !isListening)
            .accessibilityLabel(isListening ? "Stop listening" : "Start listening")

            Button {} label: {
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

            Button {} label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.graptionAccent)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.graptionAccent, lineWidth: 1))
            }
            .accessibilityLabel("Volume")
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
