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

    /// Demo fallback when `speaker(from:to:)` is "unknown": the face with the highest mean
    /// score around the segment (missing frames count as zero), ties broken by how often the
    /// face was seen. Nil only when no face was tracked near the segment. This always names
    /// someone, so it can be wrong; it is not the calibrated fusion rule.
    public func mostLikelySpeaker(from start: Double, to end: Double, slack: Double = 1) -> String? {
        guard start.isFinite, end.isFinite, end >= start else { return nil }
        let window = frames.filter { (start - slack...end + slack).contains($0.time) }
        guard !window.isEmpty else { return nil }
        var totals: [String: (score: Double, seen: Int)] = [:]
        for frame in window {
            for (faceID, score) in frame.scores {
                let current = totals[faceID] ?? (0, 0)
                totals[faceID] = (current.score + score, current.seen + 1)
            }
        }
        return totals.max { lhs, rhs in
            let left = lhs.value.score / Double(window.count)
            let right = rhs.value.score / Double(window.count)
            if left != right { return left < right }
            if lhs.value.seen != rhs.value.seen { return lhs.value.seen < rhs.value.seen }
            return lhs.key > rhs.key
        }?.key
    }
}
