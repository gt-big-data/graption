//
//  EnergyVAD.swift
//  Graption
//
//  Created by Derek Kwong on 10/5/26.
//

import Foundation

public final class EnergyVAD {
    private var segmentStart: TimeInterval?
    private var segmentSamples: [Float] = []
    private var silenceDuration: TimeInterval = 0

    private let threshold: Float
    private let sampleRate: Double = 16_000
    private let maxSegmentSamples = 160_000

    public init(threshold: Float) {
        precondition(threshold.isFinite && threshold > 0)
        self.threshold = threshold
    }

    public func process(
        samples: [Float],
        tStart: TimeInterval
    ) -> [AudioSegment] {
        guard !samples.isEmpty else { return [] }

        var completed: [AudioSegment] = []
        var offset = 0

        // Usually runs once. If a buffer crosses the 10-second
        // boundary, loop again to process the remaining samples.
        while offset < samples.count {
            // At 16 kHz, exactly 20 ms means 320 samples.
            // Ten seconds is exactly 500 such buffers, so those
            // buffers would not need a partial split.
            //
            // Actual buffer sizes may vary. Limit this chunk to
            // the remaining capacity to enforce the 10-second cap.
            let remainingCapacity =
                maxSegmentSamples - segmentSamples.count
            let count = min(
                remainingCapacity,
                samples.count - offset
            )

            let chunk = Array(samples[offset..<(offset + count)])
            let chunkStart = tStart + Double(offset) / sampleRate
            let duration = Double(count) / sampleRate
            let isSpeech = rms(chunk) >= threshold

            // Begin a segment when speech is detected while idle.
            if isSpeech && segmentStart == nil {
                segmentStart = chunkStart
            }

            // Ignore silence until a segment has started.
            if segmentStart != nil {
                // Keep quiet samples too, preserving pauses.
                segmentSamples.append(contentsOf: chunk)

                if isSpeech {
                    silenceDuration = 0
                } else {
                    silenceDuration += duration
                }

                // Finish after 500 ms of consecutive silence
                // or exactly 10 seconds of collected audio.
                if silenceDuration >= 0.5
                    || segmentSamples.count >= maxSegmentSamples {
                    if let segment = finishSegment() {
                        completed.append(segment)
                    }
                }
            }

            // Continue processing any samples left after a split.
            offset += count
        }

        return completed
    }

    /// Call when capture stops to emit any unfinished segment.
    public func flush() -> AudioSegment? {
        finishSegment()
    }

    /// Discard unfinished audio when cancelling a session.
    public func reset() {
        segmentStart = nil
        segmentSamples.removeAll(keepingCapacity: true)
        silenceDuration = 0
    }

    private func finishSegment() -> AudioSegment? {
        guard let start = segmentStart,
              !segmentSamples.isEmpty else {
            reset()
            return nil
        }

        // Includes trailing silence. Assumes continuous 16 kHz audio.
        let segment = AudioSegment(
            samples: segmentSamples,
            tStart: start,
            tEnd: start + Double(segmentSamples.count) / sampleRate
        )

        reset()
        return segment
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let meanSquare = samples.reduce(Float(0)) {
            $0 + $1 * $1
        } / Float(samples.count)

        return meanSquare.squareRoot()
    }
}
