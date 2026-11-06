//
//  FeatureBuilder.swift
//  GraptionVision
//
//  Turns one face in one frame into the speaker model's 96 numbers.
//  Swift mirror of ml/common/features.py. The two must produce the same values;
//  FeatureBuilderTests checks this against ml/common/fixtures/features_v1.json.
//  Spec: GRAPTION_CONTEXT.md §6 FeatureBuilder. Don't change one side without the other.
//

import CoreGraphics
import Foundation
import simd

/// The locked feature layout. Mirrors the constants in `ml/common/features.py`.
public enum FeatureSpec {
    public static let version = "features-v1"

    /// The 40 unique points of MediaPipe's `FACEMESH_LIPS`, sorted. This is the lips block order.
    public static let lipLandmarks = [
        0, 13, 14, 17, 37, 39, 40, 61, 78, 80, 81, 82, 84, 87, 88, 91, 95, 146, 178, 181,
        185, 191, 267, 269, 270, 291, 308, 310, 311, 312, 314, 317, 318, 321, 324, 375, 402,
        405, 409, 415,
    ]
    public static let noseTip = 1
    /// Iris centers, only present in the 478-point mesh.
    public static let leftEye = 468
    public static let rightEye = 473
    public static let minLandmarks = 478

    public static let blendshapeNames = [
        "jawOpen", "mouthClose", "mouthFunnel", "mouthPucker",
        "mouthLowerDownLeft", "mouthLowerDownRight", "mouthUpperUpLeft", "mouthUpperUpRight",
        "mouthStretchLeft", "mouthStretchRight", "mouthRollLower", "mouthRollUpper",
    ]

    public static let lipDim = 80
    public static let blendshapeDim = 12
    public static let headPoseDim = 3
    public static let loudnessDim = 1
    /// lips (80), blendshapes (12), head pose (3), loudness (1).
    public static let featureDim = 96
    /// Everything but loudness: what the missing-landmarks rule holds.
    public static let faceDim = featureDim - loudnessDim
    /// Model input is `[1, windowFrames, featureDim]`.
    public static let windowFrames = 15
    /// Missing-landmarks rule: hold the last good face features this many frames, then restart.
    public static let maxHeldFrames = 2

    /// A name for each of the 96 positions, e.g. "lips lm61 x", "blend jawOpen", "pose yaw".
    /// Mirrors `feature_labels()` in `features.py`.
    public static let labels: [String] =
        lipLandmarks.flatMap { ["lips lm\($0) x", "lips lm\($0) y"] }
        + blendshapeNames.map { "blend \($0)" }
        + ["pose yaw", "pose pitch", "pose roll", "loudness"]
}

public enum FeatureError: Error, Equatable {
    case tooFewLandmarks(Int)
    case zeroInterOcularDistance
    case missingBlendshapes([String])
}

/// Builds feature vectors. Math runs in `Double` (as Python does); vectors come out as `Float`
/// for the Core ML input.
public enum FeatureBuilder {
    /// The 95 face values (lips, blendshapes, head pose) for a tracked face, or nil when this
    /// frame has no landmarks or no blendshapes/matrix (a coasting face, or MediaPipe missed).
    /// Feed nil to `FeatureHistory.push` so the missing-landmarks rule applies.
    public static func faceFeatures(for track: FaceTrack, frameSize: CGSize) -> [Float]? {
        guard track.hasLandmarks, let transform = track.transform else { return nil }
        return try? faceFeatures(
            landmarks: track.landmarks,
            blendshapes: track.blendshapes,
            transform: transform,
            imageWidth: Double(frameSize.width),
            imageHeight: Double(frameSize.height)
        )
    }

    /// The full 96-value vector. Mirrors `extract_full_feature_vec`.
    public static func features(
        landmarks: [SIMD3<Float>],
        blendshapes: [String: Float],
        transform: simd_float4x4,
        imageWidth: Double,
        imageHeight: Double,
        loudness: Float
    ) throws -> [Float] {
        try faceFeatures(
            landmarks: landmarks,
            blendshapes: blendshapes,
            transform: transform,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        ) + [loudness]
    }

    public static func faceFeatures(
        landmarks: [SIMD3<Float>],
        blendshapes: [String: Float],
        transform: simd_float4x4,
        imageWidth: Double,
        imageHeight: Double
    ) throws -> [Float] {
        let values = try lipFeatures(landmarks: landmarks, imageWidth: imageWidth, imageHeight: imageHeight)
            + blendshapeFeatures(blendshapes)
            + headPose(transform)
        return values.map(Float.init)
    }

    /// 80 values: each lip point minus the nose tip, in pixels, over the inter-ocular distance.
    /// Landmarks are normalized to the full frame. Mirrors `extract_lip_features`.
    static func lipFeatures(landmarks: [SIMD3<Float>], imageWidth: Double, imageHeight: Double) throws -> [Double] {
        guard landmarks.count >= FeatureSpec.minLandmarks else {
            throw FeatureError.tooFewLandmarks(landmarks.count)
        }
        func pixel(_ index: Int) -> (x: Double, y: Double) {
            (Double(landmarks[index].x) * imageWidth, Double(landmarks[index].y) * imageHeight)
        }
        let nose = pixel(FeatureSpec.noseTip)
        let left = pixel(FeatureSpec.leftEye)
        let right = pixel(FeatureSpec.rightEye)
        let interOcularDistance = hypot(right.x - left.x, right.y - left.y)
        guard interOcularDistance > 0 else { throw FeatureError.zeroInterOcularDistance }

        var features: [Double] = []
        features.reserveCapacity(FeatureSpec.lipDim)
        for index in FeatureSpec.lipLandmarks {
            let lip = pixel(index)
            features.append((lip.x - nose.x) / interOcularDistance)
            features.append((lip.y - nose.y) / interOcularDistance)
        }
        return features
    }

    /// 12 scores in `FeatureSpec.blendshapeNames` order. Mirrors `extract_face_blendshapes`.
    static func blendshapeFeatures(_ scores: [String: Float]) throws -> [Double] {
        let missing = FeatureSpec.blendshapeNames.filter { scores[$0] == nil }
        guard missing.isEmpty else { throw FeatureError.missingBlendshapes(missing) }
        return FeatureSpec.blendshapeNames.map { Double(scores[$0]!) }
    }

    /// yaw, pitch, roll (radians) with R = Ry(yaw) Rx(pitch) Rz(roll). Mirrors `extract_head_ypr`.
    /// `simd_float4x4` is column-major, so row `r`, column `c` is `matrix[c][r]`.
    static func headPose(_ matrix: simd_float4x4) -> [Double] {
        func r(_ row: Int, _ column: Int) -> Double { Double(matrix[column][row]) }
        let yaw = atan2(r(0, 2), r(2, 2))
        let pitch = asin(max(-1.0, min(1.0, -r(1, 2))))
        let roll = atan2(r(1, 0), r(1, 1))
        return [yaw, pitch, roll]
    }

    /// Builds a `simd_float4x4` from a row-major reader such as MediaPipe's
    /// `TransformMatrix.value(atRow:column:)`.
    public static func matrix(rowMajor value: (Int, Int) -> Float) -> simd_float4x4 {
        var matrix = simd_float4x4()
        for row in 0..<4 {
            for column in 0..<4 {
                matrix[column][row] = value(row, column)
            }
        }
        return matrix
    }
}

/// One face's last 15 vectors with the missing-landmarks rule (GRAPTION_CONTEXT.md §6).
/// Mirrors `FeatureHistory` in `ml/common/features.py`.
///
/// Frame has landmarks: append it. Frame is missing landmarks: repeat the last good face
/// features with this frame's loudness, at most `maxHeldFrames` frames in a row. One more miss
/// (or a miss before any good frame) starts the history over.
public struct FeatureHistory: Sendable {
    private var frames: [[Float]] = []
    private var lastGood: [Float]?
    private var held = 0

    public init() {}

    /// `faceFeatures` is the 95 face values (or a full 96-vector, whose loudness is ignored),
    /// or nil when this frame has no landmarks.
    public mutating func push(_ faceFeatures: [Float]?, loudness: Float) {
        if let faceFeatures {
            precondition(faceFeatures.count >= FeatureSpec.faceDim, "need \(FeatureSpec.faceDim) face features")
            lastGood = Array(faceFeatures.prefix(FeatureSpec.faceDim))
            held = 0
        } else if lastGood != nil, held < FeatureSpec.maxHeldFrames {
            held += 1
        } else {
            reset()
            return
        }
        frames.append(lastGood! + [loudness])
        if frames.count > FeatureSpec.windowFrames { frames.removeFirst() }
    }

    public mutating func reset() {
        frames.removeAll()
        lastGood = nil
        held = 0
    }

    public var isFull: Bool { frames.count == FeatureSpec.windowFrames }

    /// `[windowFrames][featureDim]`, oldest first, or nil until 15 frames are buffered.
    public var window: [[Float]]? { isFull ? frames : nil }
}

/// Histories for every tracked face, keyed by face ID. A face missing from a frame's tracks
/// (no longer published by `FaceTracker`) loses its history, same as a restart.
public struct FeatureHistories: Sendable {
    public private(set) var histories: [String: FeatureHistory] = [:]

    public init() {}

    /// Call once per frame with every published track. Returns the full windows by face ID.
    @discardableResult
    public mutating func update(with tracks: [FaceTrack], frameSize: CGSize, loudness: Float) -> [String: [[Float]]] {
        let ids = Set(tracks.map(\.id))
        histories = histories.filter { ids.contains($0.key) }
        var windows: [String: [[Float]]] = [:]
        for track in tracks {
            histories[track.id, default: FeatureHistory()].push(
                FeatureBuilder.faceFeatures(for: track, frameSize: frameSize),
                loudness: loudness
            )
            if let window = histories[track.id]?.window { windows[track.id] = window }
        }
        return windows
    }

    public mutating func reset() { histories.removeAll() }
}
