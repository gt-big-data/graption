import SwiftUI
import GraptionCore

/// Past sessions saved on this phone by `LiveSession` (caption text and timings only).
struct SavedSessionsView: View {
    @State private var sessions: [SavedSession] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if sessions.isEmpty {
                Text("No saved sessions yet. Pausing captions saves the current session.")
            }
            ForEach(sessions) { session in
                NavigationLink {
                    List(session.captions) { caption in
                        CaptionRow(caption: caption)
                    }
                    .navigationTitle("Saved transcript")
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .standard))
                        Text("\(session.captions.count) captions · \(Int(session.duration.rounded())) s")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Saved Sessions")
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        do {
            sessions = try await FileSessionStore.onDevice().loadSessions()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load saved sessions. \(error.localizedDescription)"
        }
    }
}

private struct CaptionRow: View {
    let caption: SavedCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption.speakerID == "unknown" ? "Someone" : caption.speakerID)
                .font(.headline)
            Text(caption.text)
            if let tone = caption.toneTag {
                Text("Tone: \(tone)")
                    .font(.subheadline)
            }
            Text("\(caption.tStart.formatted(.number.precision(.fractionLength(1))))–\(caption.tEnd.formatted(.number.precision(.fractionLength(1)))) s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
