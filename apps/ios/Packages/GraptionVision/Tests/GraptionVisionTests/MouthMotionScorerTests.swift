import CoreGraphics
import XCTest
@testable import GraptionVision

final class MouthMotionScorerTests: XCTestCase {
    private func face(_ id: String, jaw: Float, size: CGFloat) -> FaceTrack {
        FaceTrack(id: id, box: CGRect(x: 0, y: 0, width: size, height: size),
            landmarks: [SIMD3<Float>(0, 0, 0)],
            blendshapes: ["jawOpen": jaw, "mouthFunnel": 0, "mouthPucker": 0])
    }

    func testSmallerMovingMouthWinsThenOtherSpeakerCanTakeOver() {
        var scorer = MouthMotionScorer()
        var scores: [String: Double] = [:]
        for frame in 0..<15 {
            scores = scorer.scores(for: [face("f1", jaw: frame % 2 == 0 ? 0 : 0.2, size: 0.1),
                                        face("f2", jaw: 0, size: 0.4)], at: Double(frame) / 15)
        }
        XCTAssertGreaterThan(scores["f1"] ?? 0, 0.5)
        XCTAssertEqual(scores["f2"], 0)
        for frame in 15..<35 {
            scores = scorer.scores(for: [face("f2", jaw: frame % 2 == 0 ? 0 : 0.2, size: 0.4),
                                        face("f1", jaw: 0, size: 0.1)], at: Double(frame) / 15)
        }
        XCTAssertGreaterThan(scores["f2"] ?? 0, 0.5)
        XCTAssertEqual(scores["f1"], 0)
    }

    func testStaticOpenMouthAndMissingLandmarksDoNotBecomeSpeakers() {
        var scorer = MouthMotionScorer()
        var scores: [String: Double] = [:]
        for frame in 0..<20 {
            scores = scorer.scores(for: [face("f1", jaw: 0.6, size: 0.4),
                FaceTrack(id: "f2", box: .zero)], at: Double(frame) / 15)
        }
        XCTAssertEqual(scores, ["f1": 0, "f2": 0])
        XCTAssertTrue(scorer.scores(for: [], at: 2).isEmpty)
    }
}
