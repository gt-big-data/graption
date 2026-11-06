// Parity with ml/common/features.py: reproduces every value in ml/common/fixtures/features_v1.json.
// Regenerate the fixtures with `uv run python ml/common/make_fixtures.py`, never by hand.

import CoreGraphics
import XCTest
import simd
@testable import GraptionVision

private struct Fixtures: Decodable {
    struct Blendshape: Decodable {
        let name: String
        let score: Double
    }

    struct Case: Decodable {
        let name: String
        let image_width: Double
        let image_height: Double
        let landmarks: [[Double]]
        let blendshapes: [Blendshape]
        let facial_transformation_matrix: [[Double]]
        let loudness: Double
        let expected: [Double]
    }

    struct History: Decodable {
        let has_landmarks: [Bool]
        let expected_rows: [[[Int]]?]
    }

    let feature_spec_version: String
    let feature_dim: Int
    let window_frames: Int
    let max_held_frames: Int
    let lip_landmarks: [Int]
    let blendshape_names: [String]
    let cases: [Case]
    let history: History

    static func load() throws -> Fixtures {
        // Tests/GraptionVisionTests/ -> repo root. Read in place so there is one copy of the data.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../../../../ml/common/fixtures/features_v1.json")
            .standardized
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }
}

private extension Fixtures.Case {
    var landmarkPoints: [SIMD3<Float>] { landmarks.map { SIMD3(Float($0[0]), Float($0[1]), Float($0[2])) } }
    var scores: [String: Float] {
        Dictionary(uniqueKeysWithValues: blendshapes.map { ($0.name, Float($0.score)) })
    }
    var matrix: simd_float4x4 {
        FeatureBuilder.matrix { Float(facial_transformation_matrix[$0][$1]) }
    }
}

final class FeatureBuilderTests: XCTestCase {
    private var fixtures: Fixtures!

    override func setUpWithError() throws {
        fixtures = try Fixtures.load()
    }

    func testSpecConstantsMatchPython() {
        XCTAssertEqual(fixtures.feature_spec_version, FeatureSpec.version)
        XCTAssertEqual(fixtures.feature_dim, FeatureSpec.featureDim)
        XCTAssertEqual(fixtures.window_frames, FeatureSpec.windowFrames)
        XCTAssertEqual(fixtures.max_held_frames, FeatureSpec.maxHeldFrames)
        XCTAssertEqual(fixtures.lip_landmarks, FeatureSpec.lipLandmarks)
        XCTAssertEqual(fixtures.blendshape_names, FeatureSpec.blendshapeNames)
        XCTAssertEqual(
            FeatureSpec.lipDim + FeatureSpec.blendshapeDim + FeatureSpec.headPoseDim + FeatureSpec.loudnessDim,
            FeatureSpec.featureDim
        )
    }

    /// Double math against Python's float64 math: should agree to rounding error.
    func testDoublePrecisionMatchesPython() throws {
        XCTAssertFalse(fixtures.cases.isEmpty)
        for fixture in fixtures.cases {
            let values = try FeatureBuilder.lipFeatures(
                landmarks: fixture.landmarkPoints,
                imageWidth: fixture.image_width,
                imageHeight: fixture.image_height
            )
                + FeatureBuilder.blendshapeFeatures(fixture.scores)
                + FeatureBuilder.headPose(fixture.matrix)
                + [Double(Float(fixture.loudness))]
            XCTAssertEqual(values.count, fixture.expected.count, fixture.name)
            for (index, (actual, expected)) in zip(values, fixture.expected).enumerated() {
                XCTAssertEqual(actual, expected, accuracy: 1e-12, "\(fixture.name)[\(index)]")
            }
        }
    }

    /// The Float vector the model will see, through the public API.
    func testPublicVectorMatchesPython() throws {
        for fixture in fixtures.cases {
            let vector = try FeatureBuilder.features(
                landmarks: fixture.landmarkPoints,
                blendshapes: fixture.scores,
                transform: fixture.matrix,
                imageWidth: fixture.image_width,
                imageHeight: fixture.image_height,
                loudness: Float(fixture.loudness)
            )
            XCTAssertEqual(vector.count, FeatureSpec.featureDim)
            for (index, (actual, expected)) in zip(vector, fixture.expected).enumerated() {
                XCTAssertEqual(actual, Float(expected), accuracy: 1e-6, "\(fixture.name)[\(index)]")
            }
        }
    }

    func testTrackPathMatchesPython() throws {
        let fixture = fixtures.cases[1]
        let track = FaceTrack(
            id: "f1",
            box: .zero,
            landmarks: fixture.landmarkPoints,
            blendshapes: fixture.scores,
            transform: fixture.matrix
        )
        let size = CGSize(width: fixture.image_width, height: fixture.image_height)
        let face = try XCTUnwrap(FeatureBuilder.faceFeatures(for: track, frameSize: size))
        for (actual, expected) in zip(face, fixture.expected.prefix(FeatureSpec.faceDim)) {
            XCTAssertEqual(actual, Float(expected), accuracy: 1e-6)
        }
        XCTAssertEqual(face.count, FeatureSpec.faceDim)
        // No landmarks this frame (coasting or a MediaPipe miss): nil, so the history rule applies.
        XCTAssertNil(FeatureBuilder.faceFeatures(for: FaceTrack(id: "f1", box: .zero), frameSize: size))
    }

    func testRejectsBadInput() {
        let fixture = fixtures.cases[0]
        XCTAssertThrowsError(
            try FeatureBuilder.lipFeatures(landmarks: Array(fixture.landmarkPoints.prefix(468)), imageWidth: 1, imageHeight: 1)
        ) { XCTAssertEqual($0 as? FeatureError, .tooFewLandmarks(468)) }
        XCTAssertThrowsError(
            try FeatureBuilder.lipFeatures(landmarks: Array(repeating: SIMD3(0.5, 0.5, 0), count: 478), imageWidth: 1, imageHeight: 1)
        ) { XCTAssertEqual($0 as? FeatureError, .zeroInterOcularDistance) }
        XCTAssertThrowsError(try FeatureBuilder.blendshapeFeatures(["jawOpen": 0.1]))
    }

    /// Replays the Python missing-landmarks sequence and checks every window row by source frame.
    func testMissingLandmarksRuleMatchesPython() {
        func faceFeatures(_ frame: Int) -> [Float] {
            (0..<FeatureSpec.faceDim).map { Float(Double(frame) + Double($0) / 1000) }
        }
        var history = FeatureHistory()
        let pattern = fixtures.history.has_landmarks
        XCTAssertEqual(pattern.count, fixtures.history.expected_rows.count)
        for (frame, hasLandmarks) in pattern.enumerated() {
            history.push(hasLandmarks ? faceFeatures(frame) : nil, loudness: -Float(frame))
            let expected = fixtures.history.expected_rows[frame]
            guard let expected else {
                XCTAssertNil(history.window, "frame \(frame)")
                continue
            }
            guard let window = history.window else {
                XCTFail("frame \(frame): expected a window")
                continue
            }
            let actual = window.map { row in [Int(row[0].rounded()), Int((-row[FeatureSpec.faceDim]).rounded())] }
            XCTAssertEqual(actual, expected, "frame \(frame)")
            for (row, pair) in zip(window, expected) {
                XCTAssertEqual(Array(row.prefix(FeatureSpec.faceDim)), faceFeatures(pair[0]), "frame \(frame)")
            }
        }
    }

    func testHistoriesDropFacesThatDisappear() {
        let fixture = fixtures.cases[0]
        let size = CGSize(width: fixture.image_width, height: fixture.image_height)
        let good = FaceTrack(id: "f1", box: .zero, landmarks: fixture.landmarkPoints, blendshapes: fixture.scores, transform: fixture.matrix)
        var histories = FeatureHistories()
        for _ in 0..<FeatureSpec.windowFrames {
            histories.update(with: [good], frameSize: size, loudness: 0)
        }
        XCTAssertEqual(histories.update(with: [good], frameSize: size, loudness: 0)["f1"]?.count, 15)
        histories.update(with: [], frameSize: size, loudness: 0)
        XCTAssertNil(histories.histories["f1"])
        XCTAssertNil(histories.update(with: [good], frameSize: size, loudness: 0)["f1"])
    }
}

// MARK: Real faces

/// Real MediaPipe output on the repo's placeholder photo, saved by ml/common/capture_faces.py
/// along with the 96 numbers Python computed from it.
private struct RealFaces: Decodable {
    struct Face: Decodable {
        let name: String
        let landmarks: [[Double]]
        let blendshapes: [Fixtures.Blendshape]
        let facial_transformation_matrix: [[Double]]
        let expected: [Double]
    }

    let feature_spec_version: String
    let source_image: String
    let mediapipe_version: String
    let image_width: Double
    let image_height: Double
    let loudness: Double
    let labels: [String]
    let faces: [Face]

    static func load() throws -> RealFaces {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../../../../ml/common/fixtures/real_faces_v1.json")
            .standardized
        return try JSONDecoder().decode(RealFaces.self, from: Data(contentsOf: url))
    }
}

final class RealFaceFeatureTests: XCTestCase {
    /// Same raw MediaPipe output in, same 96 numbers out. Set GRAPTION_SHOW_FEATURES=1 to print
    /// the side-by-side table (index, label, Python, iPhone, difference).
    func testRealFacesMatchPython() throws {
        let real = try RealFaces.load()
        XCTAssertEqual(real.feature_spec_version, FeatureSpec.version)
        XCTAssertEqual(real.labels, FeatureSpec.labels)
        XCTAssertFalse(real.faces.isEmpty)
        let show = ProcessInfo.processInfo.environment["GRAPTION_SHOW_FEATURES"] == "1"

        for face in real.faces {
            let iphone = try FeatureBuilder.features(
                landmarks: face.landmarks.map { SIMD3(Float($0[0]), Float($0[1]), Float($0[2])) },
                blendshapes: Dictionary(uniqueKeysWithValues: face.blendshapes.map { ($0.name, Float($0.score)) }),
                transform: FeatureBuilder.matrix { Float(face.facial_transformation_matrix[$0][$1]) },
                imageWidth: real.image_width,
                imageHeight: real.image_height,
                loudness: Float(real.loudness)
            )
            XCTAssertEqual(iphone.count, FeatureSpec.featureDim)

            var lines = [
                "",
                "\(face.name) from \(real.source_image) (\(Int(real.image_width))x\(Int(real.image_height)), MediaPipe \(real.mediapipe_version))",
                "  idx  label                            python        iphone     |diff|",
            ]
            var worst = 0.0
            for index in 0..<FeatureSpec.featureDim {
                let python = face.expected[index]
                let phone = Double(iphone[index])
                let diff = abs(python - phone)
                worst = max(worst, diff)
                XCTAssertEqual(phone, python, accuracy: 1e-6, "\(face.name)[\(index)] \(FeatureSpec.labels[index])")
                if index == FeatureSpec.lipDim || index == FeatureSpec.lipDim + FeatureSpec.blendshapeDim
                    || index == FeatureSpec.featureDim - 1 {
                    lines.append("  ---")
                }
                lines.append(String(
                    format: "  %3d  %@ %12.6f  %12.6f  %9.1e  %@",
                    index,
                    FeatureSpec.labels[index].padding(toLength: 26, withPad: " ", startingAt: 0) as NSString,
                    python, phone, diff, (diff <= 1e-6 ? "ok" : "MISMATCH") as NSString
                ))
            }
            lines.append(String(format: "  %@: 96 values, largest difference %.1e", face.name as NSString, worst))
            if show { print(lines.joined(separator: "\n")) }
        }
    }
}
