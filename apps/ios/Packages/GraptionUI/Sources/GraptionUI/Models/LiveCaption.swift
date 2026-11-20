import Foundation

/// A single on-screen caption. Mirrors the shape of the future `caption` /
/// `tone_result` events from `schemas/events.schema.json`; `toneTag` starts
/// `nil` and is filled in after the fact, same as a real tone result arriving
/// late by `caption_id`.
public struct LiveCaption: Identifiable, Equatable {
    public let id: UUID
    public var speakerID: String
    public var speakerName: String
    public var toneTag: String?
    public var text: String
    /// True while this is a provisional (still-being-spoken) transcription;
    /// the final caption with the same id replaces it.
    public var isPartial: Bool

    public init(id: UUID = UUID(), speakerName: String, toneTag: String? = nil, text: String, speakerID: String? = nil, isPartial: Bool = false) {
        self.id = id
        self.speakerName = speakerName
        self.speakerID = speakerID ?? speakerName
        self.toneTag = toneTag
        self.text = text
        self.isPartial = isPartial
    }
}
