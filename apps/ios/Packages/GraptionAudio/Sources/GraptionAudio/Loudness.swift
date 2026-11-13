//
//  Loudness.swift
//  Graption
//
//  Created by Arjun on 11/11/26.
//

import Foundation

// Feature position 95 (`features-v1`). Mirrors the loudness section of
// ml/common/features.py; LoudnessTests checks it against
// ml/common/fixtures/loudness_v1.json. Change both sides together.
//
// 16 kHz audio is cut into back-to-back blocks of 1/15 s. A block's
// loudness is its RMS dBFS minus the median dBFS of the last 30 s of
// blocks (including itself; fewer at the start). A frame at time t uses
// the newest block that ended at or before t: past audio only.
public enum LoudnessSpec {
    public static let sampleRate = 16_000
    public static let blocksPerSecond = 15
    public static let historyBlocks = 30 * blocksPerSecond
    // Digital silence would be -inf dB; floor the level instead.
    public static let floorDBFS = -100.0
    static let floorRMS = 1e-5

    // First sample after block `index`. Block sizes alternate 1066/1067
    // so there are exactly 15 per second.
    public static func blockEnd(_ index: Int) -> Int {
        (index + 1) * sampleRate / blocksPerSecond
    }

    // Float64 math over float32 samples, summed in order (as Python).
    public static func rmsDBFS(_ samples: ArraySlice<Float>) -> Double {
        var total = 0.0
        for sample in samples {
            let value = Double(sample)
            total += value * value
        }

        let rms = (total / Double(samples.count)).squareRoot()
        return rms <= floorRMS ? floorDBFS : 20 * log10(rms)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

// Streaming loudness over one continuous audio stream. Times are seconds
// from the stream's first sample. Push audio in any chunk sizes.
public struct LoudnessTracker {
    public struct Block: Equatable, Sendable {
        public let endTime: TimeInterval
        public let loudness: Double
    }

    private var levels: [Double] = []
    private var pending: [Float] = []
    private var block = 0

    public init() {}

    // One entry per block these samples finished.
    public mutating func push(_ samples: [Float]) -> [Block] {
        pending.append(contentsOf: samples)
        var finished: [Block] = []

        while true {
            let start = block == 0 ? 0 : LoudnessSpec.blockEnd(block - 1)
            let size = LoudnessSpec.blockEnd(block) - start
            guard pending.count >= size else { return finished }

            levels.append(LoudnessSpec.rmsDBFS(pending[..<size]))
            pending.removeFirst(size)
            if levels.count > LoudnessSpec.historyBlocks {
                levels.removeFirst()
            }

            finished.append(Block(
                endTime: Double(LoudnessSpec.blockEnd(block))
                    / Double(LoudnessSpec.sampleRate),
                loudness: levels.last! - LoudnessSpec.median(levels)
            ))
            block += 1
        }
    }
}

// Live loudness for the speaker model. MicrophoneCapture feeds it from the
// audio queue; the camera reads `loudness(at:)` once per frame.
public final class LoudnessMeter: @unchecked Sendable {
    // Blocks kept for lookups; frames are never this far behind the mic.
    static let recentBlocks = 2 * LoudnessSpec.blocksPerSecond

    private let lock = NSLock()
    private var tracker = LoudnessTracker()
    private var streamStart: TimeInterval?
    private var samplesSeen = 0
    private var recent: [LoudnessTracker.Block] = []

    public init() {}

    // 16 kHz mono samples starting at session time `tStart`.
    public func process(samples: [Float], tStart: TimeInterval) {
        lock.withLock {
            if let start = streamStart {
                let expected = start
                    + Double(samplesSeen) / Double(LoudnessSpec.sampleRate)
                // A gap (e.g. capture restarted after an error) breaks
                // the block grid, so loudness starts over.
                if abs(tStart - expected) > 1 / Double(LoudnessSpec.blocksPerSecond) {
                    resetLocked()
                }
            }

            let start = streamStart ?? tStart
            streamStart = start
            samplesSeen += samples.count

            for block in tracker.push(samples) {
                recent.append(LoudnessTracker.Block(
                    endTime: start + block.endTime,
                    loudness: block.loudness
                ))
            }
            if recent.count > Self.recentBlocks {
                recent.removeFirst(recent.count - Self.recentBlocks)
            }
        }
    }

    // Position 95 for a frame at session time `t`; 0 before any block.
    public func loudness(at t: TimeInterval) -> Float {
        lock.withLock {
            recent.last { $0.endTime <= t }.map { Float($0.loudness) } ?? 0
        }
    }

    public func reset() {
        lock.withLock { resetLocked() }
    }

    private func resetLocked() {
        tracker = LoudnessTracker()
        streamStart = nil
        samplesSeen = 0
        recent.removeAll()
    }
}
