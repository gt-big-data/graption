import Foundation

/// Local storage records, separate from the generated network event contract.
/// Only these explicitly listed fields can reach disk; no audio or raw events.
public struct SavedCaption: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let speakerID: String
    public var toneTag: String?
    public var toneProbs: [String: Double]?
    public var toneScores: [String: Double]?
    public let tStart: Double
    public let tEnd: Double
    public var modelVersions: [String: String]

    public init(id: UUID = UUID(), text: String, speakerID: String,
                toneTag: String? = nil, tStart: Double, tEnd: Double,
                modelVersions: [String: String], toneProbs: [String: Double]? = nil,
                toneScores: [String: Double]? = nil) {
        self.id = id
        self.text = text
        self.speakerID = speakerID
        self.toneTag = toneTag
        self.tStart = tStart
        self.tEnd = tEnd
        self.modelVersions = modelVersions
        self.toneProbs = toneProbs
        self.toneScores = toneScores
    }
}

public struct SavedSoundEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let t: Double
    public let confidence: Double
    public let modelVersion: String

    public init(id: UUID = UUID(), label: String, t: Double, confidence: Double,
                modelVersion: String) {
        self.id = id
        self.label = label
        self.t = t
        self.confidence = confidence
        self.modelVersion = modelVersion
    }
}

public struct SavedSession: Codable, Equatable, Identifiable, Sendable {
    public let storageVersion: Int
    public let id: UUID
    /// Wall date for display only; caption times and duration are monotonic offsets.
    public let startedAt: Date
    public var duration: Double
    public var captions: [SavedCaption]
    public var title: String?
    public var soundEvents: [SavedSoundEvent]?
    /// A durable, redacted deletion marker prevents offline retry from restoring a meeting.
    public var deletedAt: Date?

    public var displayTitle: String {
        title ?? "Meeting \(startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    public init(id: UUID = UUID(), startedAt: Date = Date(), duration: Double,
                captions: [SavedCaption], title: String? = nil,
                soundEvents: [SavedSoundEvent] = []) {
        storageVersion = 2
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.captions = captions
        self.title = title
        self.soundEvents = soundEvents
    }
}

public protocol SessionStore: Sendable {
    func save(_ session: SavedSession) async throws
    func loadSessions() async throws -> [SavedSession]
    func loadSyncSessions() async throws -> [SavedSession]
}

public extension SessionStore {
    func loadSyncSessions() async throws -> [SavedSession] { try await loadSessions() }
}

public enum SessionStorageError: Error {
    case unsupportedVersion(Int)
    case invalidTimings
}

/// One atomic JSON file per session in private Application Support, excluded from backup.
public actor FileSessionStore: SessionStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func onDevice() throws -> FileSessionStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return FileSessionStore(directory: support.appendingPathComponent("Sessions", isDirectory: true))
    }

    public func save(_ session: SavedSession) throws {
        var session = session
        // Live recorders may still have a pre-rename snapshot or a late tone result.
        if let existing = try read(session.id) {
            guard existing.deletedAt == nil else { return }
            session.title = existing.title
        }
        try write(session)
    }

    private func write(_ session: SavedSession) throws {
        try validate(session)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directoryURL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directoryURL.setResourceValues(values)
        let data = try JSONEncoder().encode(session)
        let url = directory.appendingPathComponent(session.id.uuidString).appendingPathExtension("json")
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    public func loadSessions() throws -> [SavedSession] {
        try loadSyncSessions().filter { $0.deletedAt == nil }
    }

    public func loadSyncSessions() throws -> [SavedSession] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        return try urls.map { url in
            let session = try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: url))
            try validate(session)
            return session
        }.sorted { $0.startedAt > $1.startedAt }
    }

    public func rename(_ id: UUID, title: String) throws {
        guard var session = try read(id), session.deletedAt == nil else { return }
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        session.title = title.isEmpty ? nil : title
        try write(session)
    }

    public func delete(_ id: UUID) throws {
        guard var session = try read(id), session.deletedAt == nil else { return }
        session.deletedAt = Date()
        session.title = nil
        session.captions = []
        session.soundEvents = []
        session.duration = 0
        try write(session)
    }

    public func prune(olderThan cutoff: Date, excluding activeID: UUID? = nil) throws {
        for session in try loadSessions() where session.startedAt < cutoff && session.id != activeID {
            try delete(session.id)
        }
    }

    private func read(_ id: UUID) throws -> SavedSession? {
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: url))
        try validate(session)
        return session
    }

    private func validate(_ session: SavedSession) throws {
        guard [1, 2].contains(session.storageVersion) else {
            throw SessionStorageError.unsupportedVersion(session.storageVersion)
        }
        let probabilities = session.captions.compactMap(\.toneProbs).flatMap { $0.values }
        let scores = session.captions.compactMap(\.toneScores).flatMap { $0.values }
        let sounds = session.soundEvents ?? []
        guard probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              scores.allSatisfy(\.isFinite),
              sounds.allSatisfy({ $0.t.isFinite && $0.t >= 0 && $0.t <= session.duration
                  && $0.confidence.isFinite && (0...1).contains($0.confidence) }),
              session.duration.isFinite, session.duration >= 0,
              Set(session.captions.map(\.id)).count == session.captions.count,
              session.captions.allSatisfy({
                  $0.tStart.isFinite && $0.tEnd.isFinite && $0.tStart >= 0
                      && $0.tEnd >= $0.tStart && $0.tEnd <= session.duration
              }) else { throw SessionStorageError.invalidTimings }
    }
}
