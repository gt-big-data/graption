import Foundation
import XCTest
@testable import GraptionCore

final class SessionExportTests: XCTestCase {
    func testMatchesSharedExample() throws {
        let formatter = ISO8601DateFormatter()
        let sessions = [
            SavedSession(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, startedAt: formatter.date(from: "2026-01-02T10:00:00Z")!, duration: 5, captions: [
                SavedCaption(id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!, text: "Hello, everyone.", speakerID: "f1", toneTag: "excited", tStart: 0, tEnd: 2, modelVersions: ["asr": "whisperkit-base.en"]),
                SavedCaption(id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!, text: "See you soon.", speakerID: "unknown", tStart: 2.5, tEnd: 5, modelVersions: ["asr": "whisperkit-base.en"])]),
            SavedSession(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, startedAt: formatter.date(from: "2026-01-01T10:00:00Z")!, duration: 2, captions: [
                SavedCaption(id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!, text: "Good morning.", speakerID: "f2", tStart: 0, tEnd: 2, modelVersions: ["asr": "whisperkit-base.en"])])
        ]
        let data = try SessionExport.encode(sessions, exportedAt: formatter.date(from: "2026-01-02T12:00:00Z")!)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try Data(contentsOf: root.deletingLastPathComponent().appendingPathComponent("schemas/fixtures/session_export.example.json"))
        let actual = try JSONSerialization.jsonObject(with: data) as! NSDictionary
        let expected = try JSONSerialization.jsonObject(with: fixture) as! NSDictionary
        // UUID letter case is not significant.
        let actualText = String(data: try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]), encoding: .utf8)!.lowercased()
        let expectedText = String(data: try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]), encoding: .utf8)!.lowercased()
        XCTAssertEqual(actualText, expectedText)
    }
}
