import SwiftUI
import GraptionCore

public struct CaptionBubbleView: View {
    let caption: LiveCaption

    public init(caption: LiveCaption) {
        self.caption = caption
    }
    /// Locked see-through. 0 is a solid box, 1 is nearly invisible.
    private let seeThrough = 0.68

    public var body: some View {
        let speakerColor = colorForSpeaker(caption.speakerID)

        return VStack(alignment: .leading, spacing: 4) {
            // Speaker on the left, tone chip in the top-right corner.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(caption.speakerName)
                    .font(.footnote.bold())
                    .foregroundStyle(speakerColor)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let tag = caption.toneTag {
                    Text(tag)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.5))
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                        .accessibilityLabel("Tone: \(tag)")
                }
            }

            Text(caption.text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(1 - seeThrough * 0.85)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.55 * (1 - seeThrough)))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(speakerColor.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06 + (1 - seeThrough) * 0.2), radius: 12, y: 6)
        .animation(.easeOut(duration: 0.25), value: caption.toneTag)
    }
    }

#Preview {
    CaptionBubbleView(caption: LiveCaption(speakerName: "Daniel", toneTag: "Question", text: "Say that again?"))
        .padding()
        .background(Color.graptionBackground)
}
