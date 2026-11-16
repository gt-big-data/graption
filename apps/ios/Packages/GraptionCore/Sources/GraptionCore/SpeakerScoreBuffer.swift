/// Bounded scores on the same phone monotonic session clock as microphone segments.
/// Resolve at segment delivery, before ASR queue delay can age scores out of the buffer.
public struct SpeakerScoreBuffer {
    private var frames: [(time: Double, scores: [String: Double])] = []
    public init() {}

    public mutating func append(_ scores: [String: Double], at time: Double) {
        guard time.isFinite, time >= 0 else { return }
        frames.removeAll { $0.time < time - 15 }
        frames.append((time, scores.filter { $0.value.isFinite }))
    }

    public func speaker(from start: Double, to end: Double) -> String {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return "unknown" }
        let window = frames.filter { (start...end).contains($0.time) }
        guard window.count >= 3, let first = window.first, let last = window.last,
              last.time - first.time >= (end - start) * 0.5 else { return "unknown" }
        let faceIDs = Set(window.flatMap { $0.scores.keys })
        // Missing faces contribute zero, so a briefly visible mouth cannot win an entire segment.
        let samples = window.flatMap { frame in
            faceIDs.map { (time: frame.time, faceID: $0, score: frame.scores[$0] ?? 0) }
        }
        return captionSpeaker(from: samples, during: start...end)
    }
}
