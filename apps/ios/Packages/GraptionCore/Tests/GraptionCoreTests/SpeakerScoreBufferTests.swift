import XCTest
@testable import GraptionCore

final class SpeakerScoreBufferTests: XCTestCase {
    func testDifferentWindowsRetainDifferentSpeakerIDsAndAmbiguityIsUnknown() {
        var buffer = SpeakerScoreBuffer()
        for frame in 0..<40 {
            buffer.append(frame < 20 ? ["f1": 0.9, "f2": 0.1] : ["f1": 0.1, "f2": 0.9],
                at: Double(frame) / 10)
        }
        XCTAssertEqual(buffer.speaker(from: 0, to: 1.9), "f1")
        XCTAssertEqual(buffer.speaker(from: 2, to: 3.9), "f2")
        XCTAssertEqual(buffer.speaker(from: 0, to: 3.9), "unknown")
        XCTAssertEqual(buffer.speaker(from: 5, to: 6), "unknown")
        buffer.append(["f3": 0.9], at: 20)
        XCTAssertEqual(buffer.speaker(from: 0, to: 2), "unknown")
    }

    func testMostLikelySpeakerAlwaysNamesATrackedFace() {
        var buffer = SpeakerScoreBuffer()
        XCTAssertNil(buffer.mostLikelySpeaker(from: 0, to: 1))
        for frame in 0..<40 {
            buffer.append(frame < 20 ? ["f1": 0.9, "f2": 0.1] : ["f1": 0.1, "f2": 0.9],
                at: Double(frame) / 10)
        }
        // Ambiguous for the strict rule, but f2 moved slightly more around 1.5-3.9 s.
        XCTAssertEqual(buffer.speaker(from: 0, to: 3.9), "unknown")
        XCTAssertNotNil(buffer.mostLikelySpeaker(from: 0, to: 3.9))
        XCTAssertEqual(buffer.mostLikelySpeaker(from: 2.5, to: 3.9), "f2")
        // Nobody moving: the face seen most often wins.
        var still = SpeakerScoreBuffer()
        for frame in 0..<10 { still.append(frame < 3 ? ["f1": 0, "f2": 0] : ["f2": 0], at: Double(frame) / 10) }
        XCTAssertEqual(still.mostLikelySpeaker(from: 0, to: 0.9), "f2")
        XCTAssertNil(still.mostLikelySpeaker(from: 5, to: 6))
    }

    func testBriefAppearanceAndSparseEvidenceStayUnknown() {
        var buffer = SpeakerScoreBuffer()
        buffer.append(["f1": 1], at: 0)
        XCTAssertEqual(buffer.speaker(from: 0, to: 1), "unknown")
        for frame in 1...10 { buffer.append([:], at: Double(frame) / 10) }
        XCTAssertEqual(buffer.speaker(from: 0, to: 1), "unknown")
    }
}
