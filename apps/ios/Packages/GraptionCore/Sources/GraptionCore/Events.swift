// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let events = try Events(json)

import Foundation

/// Graption event contract v1.3 (docs/GRAPTION_CONTEXT.md section 5). All times are seconds
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
/// Tags shown on screen are excited | upset | calm | null for every backend. Custom
/// 6-emotion model: happy -> excited, anger -> upset (only when its probability is at least
/// TAG_THRESHOLD, default 0.6, and it is the argmax); neutral, sad, fear and disgust ->
/// null; never calm (CREMA-D has no calm clips). audeering baseline: arousal/valence
/// thresholds (docs/GRAPTION_CONTEXT.md section 7).
///
/// Tone server -> client. Malformed request rejected; connection stays open. Request is
/// echoed only to the originating client, never stored or logged.
///
/// Phone -> optional Mac ASR server. Completed 16 kHz mono PCM16 segment, at most 10
/// seconds. Audio stays in memory only.
///
/// Optional Mac ASR -> phone. One final response per request. Non-ok status requires local
/// fallback; no speaker decision is made here.
// MARK: - Events
public struct Events: Codable, Sendable {
    public let faces: [EventsSchema]?
    public let schemaVersion: SchemaVersion
    public let sessionID: String
    public let t: Double?
    public let type: EventsType
    public let captionID: String?
    public let modelVersions: [String: String]?
    /// Face id chosen by fusion, or "unknown" (off-screen/ambiguous; shown as "Someone").
    public let speakerID: String?
    public let tEnd: Double?
    public let tStart: Double?
    public let text: String?
    public let confidence: Double?
    public let label: String?
    /// PCM16 mono little-endian. Never written to disk or logs.
    ///
    /// PCM16 mono little-endian; never stored or logged.
    public let audioB64: String?
    public let sampleRate: Int?
    public let caption: CaptionClass?
    public let toneTag: String?
    public let latencyMS: [String: Double]?
    public let modelVersion: String?
    public let probs: Probs?
    public let scores: Scores?
    public let tag: String?
    public let code: String?
    public let message: String?
    /// Exact received text, or base64 for an unsupported binary frame. May contain audio: never
    /// store or log.
    public let request: String?
    public let requestEncoding: RequestEncoding?
    public let status: Status?

    public enum CodingKeys: String, CodingKey {
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
        case scores = "scores"
        case tag = "tag"
        case code = "code"
        case message = "message"
        case request = "request"
        case requestEncoding = "request_encoding"
        case status = "status"
    }

    public init(faces: [EventsSchema]?, schemaVersion: SchemaVersion, sessionID: String, t: Double?, type: EventsType, captionID: String?, modelVersions: [String: String]?, speakerID: String?, tEnd: Double?, tStart: Double?, text: String?, confidence: Double?, label: String?, audioB64: String?, sampleRate: Int?, caption: CaptionClass?, toneTag: String?, latencyMS: [String: Double]?, modelVersion: String?, probs: Probs?, scores: Scores?, tag: String?, code: String?, message: String?, request: String?, requestEncoding: RequestEncoding?, status: Status?) {
        self.faces = faces
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.t = t
        self.type = type
        self.captionID = captionID
        self.modelVersions = modelVersions
        self.speakerID = speakerID
        self.tEnd = tEnd
        self.tStart = tStart
        self.text = text
        self.confidence = confidence
        self.label = label
        self.audioB64 = audioB64
        self.sampleRate = sampleRate
        self.caption = caption
        self.toneTag = toneTag
        self.latencyMS = latencyMS
        self.modelVersion = modelVersion
        self.probs = probs
        self.scores = scores
        self.tag = tag
        self.code = code
        self.message = message
        self.request = request
        self.requestEncoding = requestEncoding
        self.status = status
    }
}

// MARK: Events convenience initializers and mutators

public extension Events {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Events.self, from: data)
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
        type: EventsType? = nil,
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
        scores: Scores?? = nil,
        tag: String?? = nil,
        code: String?? = nil,
        message: String?? = nil,
        request: String?? = nil,
        requestEncoding: RequestEncoding?? = nil,
        status: Status?? = nil
    ) -> Events {
        return Events(
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
            scores: scores ?? self.scores,
            tag: tag ?? self.tag,
            code: code ?? self.code,
            message: message ?? self.message,
            request: request ?? self.request,
            requestEncoding: requestEncoding ?? self.requestEncoding,
            status: status ?? self.status
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
public struct CaptionClass: Codable, Sendable {
    public let captionID: String
    public let modelVersions: [String: String]
    public let schemaVersion: SchemaVersion
    public let sessionID: String
    /// Face id chosen by fusion, or "unknown" (off-screen/ambiguous; shown as "Someone").
    public let speakerID: String
    public let tEnd: Double
    public let tStart: Double
    public let text: String
    public let type: CaptionType

    public enum CodingKeys: String, CodingKey {
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

    public init(captionID: String, modelVersions: [String: String], schemaVersion: SchemaVersion, sessionID: String, speakerID: String, tEnd: Double, tStart: Double, text: String, type: CaptionType) {
        self.captionID = captionID
        self.modelVersions = modelVersions
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.speakerID = speakerID
        self.tEnd = tEnd
        self.tStart = tStart
        self.text = text
        self.type = type
    }
}

// MARK: CaptionClass convenience initializers and mutators

public extension CaptionClass {
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

public enum SchemaVersion: String, Codable, Sendable {
    case the13 = "1.3"
}

public enum CaptionType: String, Codable, Sendable {
    case caption = "caption"
}

// MARK: - EventsSchema
public struct EventsSchema: Codable, Sendable {
    /// [x, y, w, h]
    public let bbox: [Double]
    public let faceID: String
    /// Smoothed p(speaking).
    public let p: Double

    public enum CodingKeys: String, CodingKey {
        case bbox = "bbox"
        case faceID = "face_id"
        case p = "p"
    }

    public init(bbox: [Double], faceID: String, p: Double) {
        self.bbox = bbox
        self.faceID = faceID
        self.p = p
    }
}

// MARK: EventsSchema convenience initializers and mutators

public extension EventsSchema {
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
public struct Probs: Codable, Sendable {
    public let anger: Double
    public let disgust: Double
    public let fear: Double
    public let happy: Double
    public let neutral: Double
    public let sad: Double

    public enum CodingKeys: String, CodingKey {
        case anger = "anger"
        case disgust = "disgust"
        case fear = "fear"
        case happy = "happy"
        case neutral = "neutral"
        case sad = "sad"
    }

    public init(anger: Double, disgust: Double, fear: Double, happy: Double, neutral: Double, sad: Double) {
        self.anger = anger
        self.disgust = disgust
        self.fear = fear
        self.happy = happy
        self.neutral = neutral
        self.sad = sad
    }
}

// MARK: Probs convenience initializers and mutators

public extension Probs {
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

public enum RequestEncoding: String, Codable, Sendable {
    case base64 = "base64"
    case text = "text"
}

// MARK: - Scores
public struct Scores: Codable, Sendable {
    public let arousal: Double
    public let dominance: Double
    public let valence: Double

    public enum CodingKeys: String, CodingKey {
        case arousal = "arousal"
        case dominance = "dominance"
        case valence = "valence"
    }

    public init(arousal: Double, dominance: Double, valence: Double) {
        self.arousal = arousal
        self.dominance = dominance
        self.valence = valence
    }
}

// MARK: Scores convenience initializers and mutators

public extension Scores {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Scores.self, from: data)
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
        arousal: Double? = nil,
        dominance: Double? = nil,
        valence: Double? = nil
    ) -> Scores {
        return Scores(
            arousal: arousal ?? self.arousal,
            dominance: dominance ?? self.dominance,
            valence: valence ?? self.valence
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Status: String, Codable, Sendable {
    case busy = "busy"
    case error = "error"
    case ok = "ok"
    case unavailable = "unavailable"
}

public enum EventsType: String, Codable, Sendable {
    case asrRequest = "asr_request"
    case asrResult = "asr_result"
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
