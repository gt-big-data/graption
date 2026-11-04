import SwiftUI

public struct TranscriptScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let captions: [TranscriptCaption]
    private let onHome: (() -> Void)?

    public init(
        captions: [TranscriptCaption] = [],
        onHome: (() -> Void)? = nil
    ) {
        self.captions = captions
        self.onHome = onHome
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Text("9:41")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.graptionAccent)

                Spacer()

                HStack(spacing: 6) {
                    Image("cellular_signal", bundle: nil)
                        .frame(width: 18, height: 16)

                    Image("wifi", bundle: nil)
                        .frame(width: 16, height: 16)

                    Image("battery", bundle: nil)
                        .frame(width: 26, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 44)

            // Navigation header
            HStack(spacing: 8) {
                Button(action: { onHome?() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))

                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.graptionAccent)
                    }
                    .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.graptionAccent)

                    Text("Graption • Text-only view")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.graptionSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(
                Rectangle()
                    .stroke(Color.graptionAccent, lineWidth: 1)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Server status
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image("disconnected_indicator", bundle: nil)
                                .frame(width: 6, height: 6)

                            Text("Mac server · Not connected")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.graptionSecondaryText)
                        }

                        Text("Captions retained from this session. No new captions while disconnected.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.graptionSecondaryText)
                            .lineSpacing(1.5 - 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Transcript panel
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Session captions")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.graptionAccent)

                            Spacer()

                            Text("\(captions.count) captions")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.graptionSecondaryText)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .border(width: 1, edges: [.bottom], color: Color.white.opacity(0.2))

                        // Caption entries
                        if captions.isEmpty {
                            VStack(spacing: 12) {
                                Spacer()
                                    .frame(height: 24)

                                Text("No captions yet")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.graptionSecondaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Spacer()
                                    .frame(height: 24)
                            }
                        } else {
                            ForEach(Array(captions.enumerated()), id: \.offset) { index, caption in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(caption.speaker)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(caption.color)

                                        Spacer()

                                        if let tone = caption.tone {
                                            Text(tone)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(Color.graptionAccent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.08))
                                                .cornerRadius(999)
                                        }
                                    }

                                    Text(caption.text)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(caption.color)
                                        .lineSpacing(1.4 - 1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 24)
                                .padding(.horizontal, 20)
                                .border(width: 1, edges: index < captions.count - 1 ? [.bottom] : [], color: Color.white.opacity(0.2))
                            }
                        }

                        // End of transcript
                        HStack {
                            Text("End of retained captions")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.graptionSecondaryText)

                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                    }
                    .background(Color.graptionBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.graptionAccent, lineWidth: 1)
                    )
                    .cornerRadius(20)
                }
                .padding(16)
            }

            Spacer()
        }
        .background(Color.graptionBackground.ignoresSafeArea())
    }
}

public struct TranscriptCaption {
    public let id: UUID
    public let speaker: String
    public let text: String
    public let tone: String?
    public let color: Color

    public init(
        id: UUID = UUID(),
        speaker: String,
        text: String,
        tone: String? = nil,
        color: Color = .graptionAccent
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.tone = tone
        self.color = color
    }
}

#Preview {
    TranscriptScreen(
        captions: [
            TranscriptCaption(speaker: "Daniel", text: "Say that again?", tone: "Question"),
            TranscriptCaption(speaker: "Helena", text: "Let's pause.", tone: "Calm"),
            TranscriptCaption(speaker: "Someone", text: "Next item.", tone: "Neutral"),
        ]
    )
}

// Helper for border styling
private struct BorderView: ViewModifier {
    let width: CGFloat
    let edges: [Edge]
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if edges.contains(.bottom) {
                    color
                        .frame(height: width)
                }
            }
    }
}

extension View {
    fileprivate func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        self.modifier(BorderView(width: width, edges: edges, color: color))
    }
}
