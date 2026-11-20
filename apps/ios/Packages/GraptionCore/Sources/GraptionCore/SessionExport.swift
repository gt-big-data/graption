import Foundation

/// Portable export, intentionally separate from the private storage representation.
public enum SessionExport {
    private struct Export: Encodable {
        let exportVersion = "2"
        let exportedAt: Date
        let appVersion: String?
        let sessions: [Session]
    }
    private struct Session: Encodable {
        let id: UUID
        let startedAt: Date
        let duration: Double
        let captions: [Caption]
        let title: String?
        let soundEvents: [SavedSoundEvent]
        let deletedAt: Date?
    }
    private struct Caption: Encodable {
        let captionId: UUID
        let text: String
        let speakerId: String
        let toneProbs: [String: Double]?
        let toneScores: [String: Double]?
        let toneTag: String?
        let tStart: Double
        let tEnd: Double
        let modelVersions: [String: String]

        enum CodingKeys: String, CodingKey {
            case captionId, text, speakerId, toneTag, tStart, tEnd, modelVersions, toneProbs, toneScores
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(captionId, forKey: .captionId)
            try container.encode(text, forKey: .text)
            try container.encode(speakerId, forKey: .speakerId)
            try container.encode(toneTag, forKey: .toneTag)
            try container.encodeIfPresent(toneProbs, forKey: .toneProbs)
            try container.encodeIfPresent(toneScores, forKey: .toneScores)
            try container.encode(tStart, forKey: .tStart)
            try container.encode(tEnd, forKey: .tEnd)
            try container.encode(modelVersions, forKey: .modelVersions)
        }
    }

    public static func encode(_ sessions: [SavedSession], exportedAt: Date = Date(),
                              appVersion: String? = nil) throws -> Data {
        let records = sessions.map { session in
            Session(id: session.id, startedAt: session.startedAt, duration: session.duration,
                    captions: session.captions.map { caption in
                Caption(captionId: caption.id, text: caption.text, speakerId: caption.speakerID,
                        toneProbs: caption.toneProbs, toneScores: caption.toneScores,
                        toneTag: caption.toneTag, tStart: caption.tStart, tEnd: caption.tEnd,
                        modelVersions: caption.modelVersions)
            }, title: session.title, soundEvents: session.soundEvents ?? [],
                    deletedAt: session.deletedAt)
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(exportedAt: exportedAt, appVersion: appVersion, sessions: records))
    }
}
