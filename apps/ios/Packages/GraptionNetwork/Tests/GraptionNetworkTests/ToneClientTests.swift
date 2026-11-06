import XCTest
@testable import GraptionNetwork
import GraptionCore

final class ToneClientTests: XCTestCase {
    func testBuildsEndpointAndEncodesSessionID() throws {
        let configuration = ToneClientConfiguration(
            serverURL: URL(string: "ws://192.168.1.8:8000")!,
            sessionID: "demo+phone"
        )
        XCTAssertEqual(
            try configuration.sessionURL().absoluteString,
            "ws://192.168.1.8:8000/ws/session?session_id=demo%2Bphone"
        )
    }

    func testToneRequestUsesSharedSchemaKeys() throws {
        let event = Events(
            faces: nil, schemaVersion: .the13,
            sessionID: "demo",
            t: nil, type: .toneRequest,
            captionID: "3f1c2a9e-8b7d-4c6e-9a01-2b3c4d5e6f70",
            modelVersions: nil, speakerID: nil, tEnd: 1.1,
            tStart: 1.0,
            text: nil, confidence: nil, label: nil, audioB64: "AAABAAIA",
            sampleRate: 16_000,
            caption: nil, toneTag: nil, latencyMS: nil, modelVersion: nil,
            probs: nil, scores: nil, tag: nil, code: nil, message: nil,
            request: nil, requestEncoding: nil, status: nil
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        XCTAssertEqual(object["type"] as? String, "tone_request")
        XCTAssertEqual(object["schema_version"] as? String, "1.3")
        XCTAssertEqual(object["session_id"] as? String, "demo")
    }
}
