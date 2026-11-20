import Foundation

/// Provisional visual activity heuristic, not a trained or calibrated probability model.
/// Scores changing mouth shapes per tracked face, never face size or detection order.
public struct MouthMotionScorer: SpeakerScorer, Sendable {
    public static let modelVersion = "mouth-motion-v1"
    private struct Sample: Sendable {
        let time: Double
        let shape: [Double]
        let movement: Double
    }
    private var histories: [String: [Sample]] = [:]
    private let names = ["jawOpen", "mouthFunnel", "mouthPucker"]

    public init() {}

    public mutating func scores(for faces: [FaceTrack], at timestamp: Double) -> [String: Double] {
        histories = histories.filter { id, _ in faces.contains { $0.id == id } }
        var scores: [String: Double] = [:]
        for face in faces {
            let shape = names.compactMap { face.blendshapes[$0].map(Double.init) }
            guard face.hasLandmarks, shape.count == names.count, shape.allSatisfy(\.isFinite) else {
                histories[face.id] = nil
                scores[face.id] = 0
                continue
            }
            var history = histories[face.id] ?? []
            if let last = history.last, timestamp <= last.time || timestamp - last.time > 0.25 {
                history = []
            }
            let movement: Double
            if let last = history.last {
                // Normalize to 15 fps so dropped frames do not inflate activity.
                let scale = min(1, (1.0 / 15) / (timestamp - last.time))
                movement = zip(shape, last.shape).map { abs($0.0 - $0.1) }.max()! * scale
            } else { movement = 0 }
            history.append(Sample(time: timestamp, shape: shape, movement: movement))
            history.removeAll { timestamp - $0.time > 0.6 }
            histories[face.id] = history
            let warmed = timestamp - (history.first?.time ?? timestamp) >= 0.2
            let average = history.reduce(0) { $0 + $1.movement } / Double(history.count)
            scores[face.id] = warmed ? min(1, average / 0.04) : 0
        }
        return scores
    }
}
