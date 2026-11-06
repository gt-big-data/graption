import Foundation
import XCTest
@testable import GraptionAudio

final class FallbackCaptionTranscriberTests: XCTestCase {
    func testRemoteFailureUsesPreparedLocalModelAndPreservesID() async throws {
        let local = FakeCaptionTranscriber(text: "local")
        let remote = FakeCaptionTranscriber(text: nil)
        let transcriber = FallbackCaptionTranscriber(remote: remote, local: local)
        try await transcriber.prepare(allowDownload: false)
        let segment = AudioSegment(samples: [0.2], tStart: 0, tEnd: 0.1)
        let result = try await transcriber.transcribe(segment)
        let prepared = await local.prepared
        XCTAssertTrue(prepared)
        XCTAssertEqual(result.captionID, segment.captionID)
        XCTAssertEqual(result.text, "local")
    }

    func testRemoteSuccessDoesNotInvokeLocalModel() async throws {
        let local = FakeCaptionTranscriber(text: "local")
        let remote = FakeCaptionTranscriber(text: "remote")
        let transcriber = FallbackCaptionTranscriber(remote: remote, local: local)
        let result = try await transcriber.transcribe(AudioSegment(samples: [0.2], tStart: 0, tEnd: 0.1))
        let localCalls = await local.calls
        XCTAssertEqual(result.text, "remote")
        XCTAssertEqual(localCalls, 0)
    }
}

private actor FakeCaptionTranscriber: CaptionTranscriber {
    let text: String?
    private(set) var prepared = false
    private(set) var calls = 0

    init(text: String?) { self.text = text }

    func prepare(allowDownload: Bool) async throws { prepared = true }

    func transcribe(_ segment: AudioSegment) async throws -> TranscriptionResult {
        calls += 1
        guard let text else { throw TranscriberError.modelNotReady }
        return TranscriptionResult(captionID: segment.captionID, text: text,
                                   tStart: segment.tStart, tEnd: segment.tEnd, asrModelVersion: "fixture")
    }
}
