// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let graptionEvent = try GraptionEvent(json)

import Foundation

/// Graption event contract v1.1 (docs/GRAPTION_CONTEXT.md section 5). All times are seconds
/// since session start on the phone's monotonic host clock. Changing this file = bump
/// schema_version and regenerate Pydantic + Swift types.
///
/// On-device. Emitted per video frame.
///
/// On-device. Emitted when WhisperKit finishes a segment.
///
/// On-device. SoundAnalysis alert (allowlisted labels, confidence >= 0.7).
///
/// Phone -> tone server. One per VAD segment.
///
/// Phone -> tone server. Final fused caption, for evaluation.
///
/// Tone server -> phone. tag is null when not confident (a wrong tag is worse than none).
/// Tag vocabulary depends on backend: custom = the 6 emotions minus neutral; audeering
/// baseline = excited | upset | calm.
///
/// Tone server -> client. Malformed request rejected; connection stays open. Request is
/// echoed only to the originating client, never stored or logged.
// MARK: - GraptionEvent
struct GraptionEvent: Codable {
    let faces: [EventsSchema]?
    let schemaVersion: SchemaVersion
    let sessionID: String
    let t: Double?
    let type: GraptionEventType
    let captionID: String?
    let modelVersions: [String: String]?
    /// Face id chosen by fusion, or "unknown" (off-screen/ambiguous; shown as "Someone").
    let speakerID: String?
    let tEnd: Double?
    let tStart: Double?
    let text: String?
    let confidence: Double?
    let label: String?
    /// PCM16 mono little-endian. Never written to disk or logs.
    let audioB64: String?
    let sampleRate: Int?
    let caption: CaptionClass?
    let toneTag: String?
    let latencyMS: [String: Double]?
    let modelVersion: String?
    let probs: Probs?
    let tag: String?
    let code: String?
    let message: String?
    /// Exact received text, or base64 for an unsupported binary frame. May contain audio: never
    /// store or log.
    let request: String?
    let requestEncoding: RequestEncoding?

    enum CodingKeys: String, CodingKey {
        case faces = "faces"
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case t = "t"
        case type = "type"
        case captionID = "caption_id"
        case modelVersions = "model_versions"
        case speakerID = "speaker_id"
        case tEnd = "t_end"
        case tStart = "t_start"
        case text = "text"
        case confidence = "confidence"
        case label = "label"
        case audioB64 = "audio_b64"
        case sampleRate = "sample_rate"
        case caption = "caption"
        case toneTag = "tone_tag"
        case latencyMS = "latency_ms"
        case modelVersion = "model_version"
        case probs = "probs"
        case tag = "tag"
        case code = "code"
        case message = "message"
        case request = "request"
        case requestEncoding = "request_encoding"
    }
}

// MARK: GraptionEvent convenience initializers and mutators

extension GraptionEvent {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(GraptionEvent.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        faces: [EventsSchema]?? = nil,
        schemaVersion: SchemaVersion? = nil,
        sessionID: String? = nil,
        t: Double?? = nil,
        type: GraptionEventType? = nil,
        captionID: String?? = nil,
        modelVersions: [String: String]?? = nil,
        speakerID: String?? = nil,
        tEnd: Double?? = nil,
        tStart: Double?? = nil,
        text: String?? = nil,
        confidence: Double?? = nil,
        label: String?? = nil,
        audioB64: String?? = nil,
        sampleRate: Int?? = nil,
        caption: CaptionClass?? = nil,
        toneTag: String?? = nil,
        latencyMS: [String: Double]?? = nil,
        modelVersion: String?? = nil,
        probs: Probs?? = nil,
        tag: String?? = nil,
        code: String?? = nil,
        message: String?? = nil,
        request: String?? = nil,
        requestEncoding: RequestEncoding?? = nil
    ) -> GraptionEvent {
        return GraptionEvent(
            faces: faces ?? self.faces,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            sessionID: sessionID ?? self.sessionID,
            t: t ?? self.t,
            type: type ?? self.type,
            captionID: captionID ?? self.captionID,
            modelVersions: modelVersions ?? self.modelVersions,
            speakerID: speakerID ?? self.speakerID,
            tEnd: tEnd ?? self.tEnd,
            tStart: tStart ?? self.tStart,
            text: text ?? self.text,
            confidence: confidence ?? self.confidence,
            label: label ?? self.label,
            audioB64: audioB64 ?? self.audioB64,
            sampleRate: sampleRate ?? self.sampleRate,
            caption: caption ?? self.caption,
            toneTag: toneTag ?? self.toneTag,
            latencyMS: latencyMS ?? self.latencyMS,
            modelVersion: modelVersion ?? self.modelVersion,
            probs: probs ?? self.probs,
            tag: tag ?? self.tag,
            code: code ?? self.code,
            message: message ?? self.message,
            request: request ?? self.request,
            requestEncoding: requestEncoding ?? self.requestEncoding
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// On-device. Emitted when WhisperKit finishes a segment.
// MARK: - CaptionClass
struct CaptionClass: Codable {
    let captionID: String
    let modelVersions: [String: String]
    let schemaVersion: SchemaVersion
    let sessionID: String
    /// Face id chosen by fusion, or "unknown" (off-screen/ambiguous; shown as "Someone").
    let speakerID: String
    let tEnd: Double
    let tStart: Double
    let text: String
    let type: CaptionType

    enum CodingKeys: String, CodingKey {
        case captionID = "caption_id"
        case modelVersions = "model_versions"
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case speakerID = "speaker_id"
        case tEnd = "t_end"
        case tStart = "t_start"
        case text = "text"
        case type = "type"
    }
}

// MARK: CaptionClass convenience initializers and mutators

extension CaptionClass {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CaptionClass.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        captionID: String? = nil,
        modelVersions: [String: String]? = nil,
        schemaVersion: SchemaVersion? = nil,
        sessionID: String? = nil,
        speakerID: String? = nil,
        tEnd: Double? = nil,
        tStart: Double? = nil,
        text: String? = nil,
        type: CaptionType? = nil
    ) -> CaptionClass {
        return CaptionClass(
            captionID: captionID ?? self.captionID,
            modelVersions: modelVersions ?? self.modelVersions,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            sessionID: sessionID ?? self.sessionID,
            speakerID: speakerID ?? self.speakerID,
            tEnd: tEnd ?? self.tEnd,
            tStart: tStart ?? self.tStart,
            text: text ?? self.text,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

enum SchemaVersion: String, Codable {
    case the11 = "1.1"
}

enum CaptionType: String, Codable {
    case caption = "caption"
}

// MARK: - EventsSchema
struct EventsSchema: Codable {
    /// [x, y, w, h]
    let bbox: [Double]
    let faceID: String
    /// Smoothed p(speaking).
    let p: Double

    enum CodingKeys: String, CodingKey {
        case bbox = "bbox"
        case faceID = "face_id"
        case p = "p"
    }
}

// MARK: EventsSchema convenience initializers and mutators

extension EventsSchema {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(EventsSchema.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        bbox: [Double]? = nil,
        faceID: String? = nil,
        p: Double? = nil
    ) -> EventsSchema {
        return EventsSchema(
            bbox: bbox ?? self.bbox,
            faceID: faceID ?? self.faceID,
            p: p ?? self.p
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Probs
struct Probs: Codable {
    let anger: Double
    let disgust: Double
    let fear: Double
    let happy: Double
    let neutral: Double
    let sad: Double

    enum CodingKeys: String, CodingKey {
        case anger = "anger"
        case disgust = "disgust"
        case fear = "fear"
        case happy = "happy"
        case neutral = "neutral"
        case sad = "sad"
    }
}

// MARK: Probs convenience initializers and mutators

extension Probs {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Probs.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        anger: Double? = nil,
        disgust: Double? = nil,
        fear: Double? = nil,
        happy: Double? = nil,
        neutral: Double? = nil,
        sad: Double? = nil
    ) -> Probs {
        return Probs(
            anger: anger ?? self.anger,
            disgust: disgust ?? self.disgust,
            fear: fear ?? self.fear,
            happy: happy ?? self.happy,
            neutral: neutral ?? self.neutral,
            sad: sad ?? self.sad
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

enum RequestEncoding: String, Codable {
    case base64 = "base64"
    case text = "text"
}

enum GraptionEventType: String, Codable {
    case caption = "caption"
    case captionLog = "caption_log"
    case sessionError = "session_error"
    case soundEvent = "sound_event"
    case speakerScores = "speaker_scores"
    case toneRequest = "tone_request"
    case toneResult = "tone_result"
}

// MARK: - Helper functions for creating encoders and decoders

func newJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    if #available(iOS 10.0, OSX 10.12, tvOS 10.0, watchOS 3.0, *) {
        decoder.dateDecodingStrategy = .iso8601
    }
    return decoder
}

func newJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    if #available(iOS 10.0, OSX 10.12, tvOS 10.0, watchOS 3.0, *) {
        encoder.dateEncodingStrategy = .iso8601
    }
    return encoder
}
