//
//  EnergyVADTests.swift
//  Graption
//
//  Created by Derek Kwong on 10/5/26.
//

import XCTest
@testable import GraptionAudio

final class EnergyVADTests: XCTestCase {
    // 320 samples = 20 ms at 16 kHz.
    private let speech = Array(repeating: Float(0.2), count: 320)
    private let silence = Array(repeating: Float(0), count: 320)

    func testManualThresholdConvertsDBFSAndActivatesAtEquality() {
        let threshold = EnergyVAD.rmsThreshold(decibels: -60)
        XCTAssertEqual(threshold, 0.001, accuracy: 0.000001)
        let vad = EnergyVAD(threshold: 0.1)
        vad.setManualThreshold(-60)

        // A single sample avoids floating-point accumulation around equality.
        _ = vad.process(samples: [threshold.nextDown], tStart: 0)
        XCTAssertNil(vad.flush())
        _ = vad.process(samples: [threshold], tStart: 0)
        XCTAssertNotNil(vad.flush())
    }

    func testReturningToAutoRestoresLastCalibration() throws {
        let vad = EnergyVAD(threshold: 0.001)
        vad.beginCalibration()
        for index in 0..<100 {
            _ = vad.process(samples: speech, tStart: Double(index) * 0.02)
        }
        let calibrated = try vad.completeCalibration()
        vad.setManualThreshold(-60)
        XCTAssertEqual(vad.threshold, 0.001, accuracy: 0.000001)
        vad.setManualThreshold(nil)
        XCTAssertEqual(vad.threshold, calibrated)
    }

    func testSilenceAloneProducesNoSegments() {
        let vad = EnergyVAD(threshold: 0.1)

        for index in 0..<100 {
            let segments = vad.process(
                samples: silence,
                tStart: Double(index) * 0.02
            )
            XCTAssertTrue(segments.isEmpty)
        }

        XCTAssertNil(vad.flush())
    }

    func testHalfSecondSilenceEndsSpeech() throws {
        let vad = EnergyVAD(threshold: 0.1)

        XCTAssertTrue(
            vad.process(samples: speech, tStart: 0).isEmpty
        )

        var completed: [AudioSegment] = []

        // Allow one extra buffer for floating-point rounding.
        for index in 1...26 {
            completed += vad.process(
                samples: silence,
                tStart: Double(index) * 0.02
            )
        }

        XCTAssertEqual(completed.count, 1)
        let segment = try XCTUnwrap(completed.first)

        XCTAssertEqual(segment.tStart, 0, accuracy: 0.000001)
        XCTAssertEqual(segment.tEnd, 0.52, accuracy: 0.020001)
        XCTAssertNil(vad.flush())
    }

    func testShortPauseKeepsSameSegment() throws {
        let vad = EnergyVAD(threshold: 0.1)

        XCTAssertTrue(
            vad.process(samples: speech, tStart: 0).isEmpty
        )

        // A 200 ms pause should not end the segment.
        for index in 1...10 {
            XCTAssertTrue(
                vad.process(
                    samples: silence,
                    tStart: Double(index) * 0.02
                ).isEmpty
            )
        }

        XCTAssertTrue(
            vad.process(samples: speech, tStart: 0.22).isEmpty
        )

        let segment = try XCTUnwrap(vad.flush())

        XCTAssertEqual(segment.tStart, 0, accuracy: 0.000001)
        XCTAssertEqual(segment.tEnd, 0.24, accuracy: 0.000001)
        XCTAssertEqual(segment.samples.count, 12 * 320)
        XCTAssertNil(vad.flush())
    }

    func testTenSecondSplitPreservesRemainder() throws {
        let vad = EnergyVAD(threshold: 0.1)

        // Deliberately crosses the limit within one input buffer.
        let samples = Array(
            repeating: Float(0.2),
            count: 160_320
        )

        let completed = vad.process(samples: samples, tStart: 2)

        XCTAssertEqual(completed.count, 1)
        let first = try XCTUnwrap(completed.first)
        let remainder = try XCTUnwrap(vad.flush())

        XCTAssertEqual(first.samples.count, 160_000)
        XCTAssertEqual(first.tStart, 2, accuracy: 0.000001)
        XCTAssertEqual(first.tEnd, 12, accuracy: 0.000001)

        XCTAssertEqual(remainder.samples.count, 320)
        XCTAssertEqual(remainder.tStart, 12, accuracy: 0.000001)
        XCTAssertEqual(remainder.tEnd, 12.02, accuracy: 0.000001)

        XCTAssertEqual(
            first.samples.count + remainder.samples.count,
            samples.count
        )
    }
}
