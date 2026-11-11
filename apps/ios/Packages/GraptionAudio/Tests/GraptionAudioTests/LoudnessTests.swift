//
//  LoudnessTests.swift
//  Graption
//
//  Created by Arjun on 11/11/26.
//

// Parity with ml/common/features.py: reproduces every value in
// ml/common/fixtures/loudness_v1.json. Regenerate the fixture with
// `uv run python ml/common/make_fixtures.py`, never by hand.

import XCTest
@testable import GraptionAudio

private struct LoudnessFixture: Decodable {
    struct LCG: Decodable {
        let multiplier: UInt64
        let increment: UInt64
        let seed: UInt64
    }

    struct Segment: Decodable {
        let samples: Int
        let amplitude: Double
    }

    let feature_spec_version: String
    let sample_rate: Int
    let blocks_per_second: Int
    let history_blocks: Int
    let floor_dbfs: Double
    let lcg: LCG
    let segments: [Segment]
    let chunk_sizes: [Int]
    let sample_checksum: Double
    let expected_end_times: [Double]
    let expected_loudness: [Double]
    let frame_times: [Double]
    let expected_frame_loudness: [Double]

    static func load() throws -> LoudnessFixture {
        // Fixtures/loudness_v1.json is a symlink to ml/common/fixtures/,
        // bundled so the simulator can read it: one copy of the data.
        guard let url = Bundle.module.url(
            forResource: "loudness_v1",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(LoudnessFixture.self, from: Data(contentsOf: url))
    }

    // Same generator as make_fixtures.loudness_samples: integer LCG noise
    // times a float32 amplitude, rounded to float32.
    func samples() -> [Float] {
        var state = lcg.seed
        var samples: [Float] = []
        for segment in segments {
            for _ in 0..<segment.samples {
                state = (lcg.multiplier * state + lcg.increment) % (1 << 32)
                let noise = Double(state) / Double(1 << 31) - 1
                samples.append(Float(segment.amplitude * noise))
            }
        }
        return samples
    }

    // The fixture's uneven chunks, with each chunk's start time.
    func chunks(of samples: [Float]) -> [(samples: [Float], tStart: TimeInterval)] {
        var chunks: [(samples: [Float], tStart: TimeInterval)] = []
        var offset = 0
        while offset < samples.count {
            let size = chunk_sizes[chunks.count % chunk_sizes.count]
            let end = min(offset + size, samples.count)
            chunks.append((
                Array(samples[offset..<end]),
                Double(offset) / Double(sample_rate)
            ))
            offset = end
        }
        return chunks
    }
}

final class LoudnessTests: XCTestCase {
    private var fixture: LoudnessFixture!

    override func setUpWithError() throws {
        fixture = try LoudnessFixture.load()
    }

    func testSpecMatchesPython() {
        XCTAssertEqual(fixture.feature_spec_version, "features-v1")
        XCTAssertEqual(fixture.sample_rate, LoudnessSpec.sampleRate)
        XCTAssertEqual(fixture.blocks_per_second, LoudnessSpec.blocksPerSecond)
        XCTAssertEqual(fixture.history_blocks, LoudnessSpec.historyBlocks)
        XCTAssertEqual(fixture.floor_dbfs, LoudnessSpec.floorDBFS)
    }

    func testGeneratedAudioMatchesPython() {
        // Exact: the generator uses integer math and IEEE rounding only.
        let checksum = fixture.samples().reduce(0.0) { $0 + Double($1) }
        XCTAssertEqual(checksum, fixture.sample_checksum)
    }

    func testBlockLoudnessMatchesPython() {
        var tracker = LoudnessTracker()
        var blocks: [LoudnessTracker.Block] = []
        for chunk in fixture.chunks(of: fixture.samples()) {
            blocks += tracker.push(chunk.samples)
        }

        XCTAssertEqual(blocks.count, fixture.expected_loudness.count)
        XCTAssertEqual(blocks.map(\.endTime), fixture.expected_end_times)
        for (index, (block, expected)) in zip(blocks, fixture.expected_loudness).enumerated() {
            // log10 may differ in the last bit between platforms.
            XCTAssertEqual(block.loudness, expected, accuracy: 1e-9, "block \(index)")
        }
    }

    func testMeterFrameLookupMatchesPython() {
        let meter = LoudnessMeter()
        // Before any audio: no block has ended yet.
        XCTAssertEqual(meter.loudness(at: 0.5), 0)

        for chunk in fixture.chunks(of: fixture.samples()) {
            meter.process(samples: chunk.samples, tStart: chunk.tStart)
        }

        let audioSeconds = fixture.expected_end_times.last!
        for (t, expected) in zip(fixture.frame_times, fixture.expected_frame_loudness)
            // The meter keeps the last 2 s for live frames.
            where t >= audioSeconds - 2 {
            XCTAssertEqual(
                meter.loudness(at: t),
                Float(expected),
                accuracy: 1e-6,
                "frame at \(t)"
            )
        }
    }

    func testMeterEarlyFramesMatchPython() {
        let meter = LoudnessMeter()
        let samples = fixture.samples()
        for (t, expected) in zip(fixture.frame_times, fixture.expected_frame_loudness) where t < 1 {
            // Live order: audio up to the frame's time, then the frame reads.
            let upTo = min(Int(t * Double(fixture.sample_rate)), samples.count)
            meter.reset()
            meter.process(samples: Array(samples[..<upTo]), tStart: 0)
            XCTAssertEqual(meter.loudness(at: t), Float(expected), accuracy: 1e-6, "frame at \(t)")
        }
    }

    func testMeterUsesSessionTimeAndRestartsAfterGap() {
        let meter = LoudnessMeter()
        let block = Array(repeating: Float(0.1), count: 1067)

        // Stream starts 5 s into the session.
        meter.process(samples: block, tStart: 5)
        XCTAssertEqual(meter.loudness(at: 5.05), 0)
        XCTAssertEqual(meter.loudness(at: 5 + 1066.0 / 16_000), 0)

        // A 1 s gap: the block grid restarts at the new time.
        let loud = Array(repeating: Float(0.5), count: 1067)
        meter.process(samples: loud, tStart: 7)
        XCTAssertEqual(meter.loudness(at: 7.1), 0, "first block after a gap is its own median")
    }

    func testSilenceIsFloored() {
        XCTAssertEqual(
            LoudnessSpec.rmsDBFS(Array(repeating: Float(0), count: 1066)[...]),
            LoudnessSpec.floorDBFS
        )
    }
}
