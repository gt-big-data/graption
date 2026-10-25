import SwiftUI

struct CaptionBubbleView: View {
    let caption: LiveCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption.speakerName)
                .font(.subheadline.bold())
                .foregroundStyle(Color.graptionAccent)

            if let tag = caption.toneTag {
                Text(tag)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.5))
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }

            Text(caption.text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .animation(.easeOut(duration: 0.25), value: caption.toneTag)
    }
}

#Preview {
    CaptionBubbleView(caption: LiveCaption(speakerName: "Daniel", toneTag: "Question", text: "Say that again?"))
        .padding()
        .background(Color.graptionBackground)
}
