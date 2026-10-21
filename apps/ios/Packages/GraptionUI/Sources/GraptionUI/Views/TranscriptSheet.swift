import SwiftUI

/// Every caption from the current session, oldest first.
struct TranscriptSheet: View {
    let captions: [LiveCaption]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Transcript")
                    .font(.headline.bold())
                    .foregroundStyle(Color.graptionAccent)
                Spacer(minLength: 8)
                CircleIconButton(systemName: "xmark", accessibilityLabel: "Close transcript") {
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.graptionAccent).frame(height: 1)
            }

            if captions.isEmpty {
                Text("No captions yet.")
                    .font(.body)
                    .foregroundStyle(Color.graptionSecondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(captions) { caption in
                            CaptionBubbleView(caption: caption)
                        }
                    }
                    .padding(16)
                }
                .defaultScrollAnchor(.bottom)
            }
        }
        .background(Color.graptionBackground.ignoresSafeArea())
    }
}

#Preview {
    TranscriptSheet(captions: [
        LiveCaption(speakerName: "Daniel", toneTag: "Question", text: "Say that again?"),
        LiveCaption(speakerName: "Someone", text: "Next item.")
    ])
}
