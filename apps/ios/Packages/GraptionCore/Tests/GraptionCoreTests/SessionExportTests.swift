import Foundation
import XCTest
@testable import GraptionCore

final class SessionExportTests: XCTestCase {
    func testV2ContainsTextOnlySoundToneAndTitle() throws {
        let caption = SavedCaption(text: "Hello", speakerID: "f2", tStart: 0, tEnd: 2,
            modelVersions: ["asr": "test", "asd": "mouth-motion-v1"],
            toneProbs: ["happy": 0.4], toneScores: ["arousal": 0.3])
        let sound = SavedSoundEvent(label: "doorbell", t: 1, confidence: 0.9, modelVersion: "sound-v1")
        let session = SavedSession(duration: 2, captions: [caption], title: "Planning", soundEvents: [sound])
        let data = try SessionExport.encode([session])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["export_version"] as? String, "2")
        let records = try XCTUnwrap(root["sessions"] as? [[String: Any]])
        XCTAssertEqual(records[0]["title"] as? String, "Planning")
        let captions = try XCTUnwrap(records[0]["captions"] as? [[String: Any]])
        XCTAssertEqual(captions[0]["speaker_id"] as? String, "f2")
        XCTAssertTrue(captions[0]["tone_tag"] is NSNull)
        XCTAssertEqual(captions[0]["tone_probs"] as? [String: Double], ["happy": 0.4])
        let sounds = try XCTUnwrap(records[0]["sound_events"] as? [[String: Any]])
        XCTAssertEqual(Set(sounds[0].keys), ["id", "label", "t", "confidence", "model_version"])
        XCTAssertEqual(sounds[0]["label"] as? String, "doorbell")
    }

    func testStorageV1StillDecodes() throws {
        let session = SavedSession(duration: 0, captions: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json["storageVersion"] = 1
        json.removeValue(forKey: "soundEvents")
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertNil(decoded.soundEvents)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.deletedAt)
    }
}
