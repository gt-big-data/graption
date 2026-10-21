import SwiftUI

struct LiveVideoFeedView<Feed: View>: View {
    /// Only the newest few captions sit over the video; the rest are in the transcript.
    static var visibleCaptionCount: Int { 3 }

    let captions: [LiveCaption]
    @ViewBuilder let feed: Feed

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                feed
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                if !captions.isEmpty {
                    captionStack
                        .padding(12)
                        // Real captions can be long sentences. Cap them to the lower half of
                        // the video and let older lines slide off the top, so faces stay visible.
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height * 0.5,
                            alignment: .bottom
                        )
                        .clipped()
                }
            }
        }
        .clipped()
    }

    // Newest at the bottom, nearest the controls, like a chat.
    private var captionStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(captions.suffix(Self.visibleCaptionCount)) { caption in
                CaptionBubbleView(caption: caption)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: captions.map(\.id))
    }
}

#Preview {
    LiveVideoFeedView(captions: [
        LiveCaption(speakerName: "Daniel", toneTag: "Question", text: "Say that again?"),
        LiveCaption(speakerName: "Helena", toneTag: "Calm", text: "Let's pause."),
        LiveCaption(speakerName: "Someone", text: "Next item.")
    ]) {
        Image("LiveVideoPlaceholder", bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
