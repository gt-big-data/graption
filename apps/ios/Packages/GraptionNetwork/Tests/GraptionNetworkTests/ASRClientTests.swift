import Foundation
import GraptionCore
import XCTest
@testable import GraptionNetwork

final class ASRClientTests: XCTestCase {
    func testUsesSeparateEndpointAndEscapesSession() throws {
        let config = ASRClientConfiguration(
            serverURL: URL(string: "ws://192.168.1.8:8000")!, sessionID: "phone+test"
        )
        XCTAssertEqual(try config.sessionURL().absoluteString,
                       "ws://192.168.1.8:8000/ws/asr?session_id=phone%2Btest")
    }

    func testRequiresMatchingNonemptyResult() throws {
        let id = UUID()
        func reply(session: String = "s", text: String = "Hello", status: String = "ok") throws -> Events {
            let json: [String: Any] = [
                "type": "asr_result", "schema_version": "1.3", "session_id": session,
                "caption_id": id.uuidString, "t_start": 1, "t_end": 2,
                "text": text, "status": status, "model_version": "test", "latency_ms": ["recv_to_send": 10]
            ]
            return try Events(data: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(try ASRClient.validate(reply(), sessionID: "s", captionID: id,
                                              tStart: 1, tEnd: 2).0, "Hello")
        for invalid in [try reply(session: "wrong"), try reply(text: " "), try reply(status: "busy")] {
            XCTAssertThrowsError(try ASRClient.validate(invalid, sessionID: "s", captionID: id,
                                                        tStart: 1, tEnd: 2))
        }
        XCTAssertThrowsError(try ASRClient.validate(reply(), sessionID: "s", captionID: UUID(),
                                                    tStart: 1, tEnd: 2))
    }
}
