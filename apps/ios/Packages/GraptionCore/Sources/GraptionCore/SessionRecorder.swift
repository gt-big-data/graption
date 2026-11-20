import Foundation

/// Session owner calls append as captions render, then end when capture stops.
/// Ending never waits for a tone response. Failed saves retain the transcript for retry.
@MainActor
public final class SessionRecorder {
    public private(set) var session: SavedSession
    public private(set) var hasEnded = false
    private let clock = SessionClock()
    private let store: any SessionStore

    public init(store: any SessionStore) {
        self.store = store
        session = SavedSession(duration: 0, captions: [])
    }

    public func append(_ caption: SavedCaption) {
        guard !hasEnded, !session.captions.contains(where: { $0.id == caption.id }) else { return }
        session.captions.append(caption)
    }

    public func appendSound(_ event: SavedSoundEvent) {
        guard !hasEnded else { return }
        if session.soundEvents == nil { session.soundEvents = [] }
        guard session.soundEvents?.contains(where: { $0.id == event.id }) == false else { return }
        session.soundEvents?.append(event)
    }

    private var lastEventTime: Double {
        max(session.captions.map(\.tEnd).max() ?? 0, session.soundEvents?.map(\.t).max() ?? 0)
    }

    /// Checkpoint live text so interruption or termination retains delivered captions.
    public func checkpoint() async throws {
        session.duration = max(clock.secondsElapsed, lastEventTime)
        try await store.save(session)
    }

    public func end() async throws {
        if !hasEnded {
            session.duration = max(clock.secondsElapsed, lastEventTime)
            hasEnded = true
        }
        try await store.save(session)
    }

    /// Route results by caption ID. A late tag updates the saved session without delaying end().
    public func applyTone(captionID: UUID, tag: String?, modelVersion: String,
                          probs: [String: Double]? = nil, scores: [String: Double]? = nil) async throws {
        guard let index = session.captions.firstIndex(where: { $0.id == captionID }) else { return }
        session.captions[index].toneTag = tag
        session.captions[index].toneProbs = probs
        session.captions[index].toneScores = scores
        session.captions[index].modelVersions["tone"] = modelVersion
        if hasEnded { try await store.save(session) }
    }
}
