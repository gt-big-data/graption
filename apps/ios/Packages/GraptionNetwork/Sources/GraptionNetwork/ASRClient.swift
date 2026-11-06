import Foundation
import GraptionCore

public enum ASRClientError: Error {
    case invalidConfiguration, invalidAudio, unavailable
}

/// Uses the same build configuration convention as P4, on a separate socket.
public struct ASRClientConfiguration: Sendable {
    public let serverURL: URL
    public let token: String?
    public let sessionID: String

    public init(serverURL: URL, token: String? = nil, sessionID: String = UUID().uuidString) {
        self.serverURL = serverURL
        self.token = token
        self.sessionID = sessionID
    }

    public static func fromAppConfiguration(bundle: Bundle = .main) -> Self? {
        guard let value = bundle.object(forInfoDictionaryKey: "GraptionASRURL") as? String,
              !value.isEmpty, let url = URL(string: value) else { return nil }
        return Self(serverURL: url, token: bundle.object(forInfoDictionaryKey: "GraptionASRToken") as? String)
    }

    public func sessionURL() throws -> URL {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
              ["ws", "wss"].contains(components.scheme ?? ""),
              let host = components.host, !host.isEmpty, components.user == nil,
              components.password == nil, components.query == nil, components.fragment == nil,
              !sessionID.isEmpty else { throw ASRClientError.invalidConfiguration }
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [prefix, "ws/asr"].filter { !$0.isEmpty }.joined(separator: "/")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        guard let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw ASRClientError.invalidConfiguration
        }
        components.percentEncodedQuery = "session_id=\(encoded)"
        guard let url = components.url else { throw ASRClientError.invalidConfiguration }
        return url
    }
}

/// Called serially by the caption pipeline. Close failed sockets so late replies
/// cannot be mistaken for subsequent captions.
public actor ASRClient {
    private let configuration: ASRClientConfiguration
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?

    public init(configuration: ASRClientConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    public func transcribe(captionID: UUID, tStart: Double, tEnd: Double, samples: [Float])
        async throws -> (text: String, modelVersion: String) {
        try Task.checkCancellation()
        guard !samples.isEmpty, samples.count <= 160_000,
              tStart.isFinite, tStart >= 0, tEnd.isFinite,
              abs(tEnd - tStart - Double(samples.count) / 16_000) <= 1 / 16_000,
              samples.allSatisfy(\.isFinite) else { throw ASRClientError.invalidAudio }
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-32768, min(32767, (Double(sample) * 32768).rounded())))
            let bits = UInt16(bitPattern: value)
            pcm.append(UInt8(bits & 255))
            pcm.append(UInt8(bits >> 8))
        }
        let event = Events(
            faces: nil, schemaVersion: .the13, sessionID: configuration.sessionID, t: nil, type: .asrRequest,
            captionID: captionID.uuidString, modelVersions: nil, speakerID: nil, tEnd: tEnd, tStart: tStart,
            text: nil, confidence: nil, label: nil, audioB64: pcm.base64EncodedString(), sampleRate: 16_000,
            caption: nil, toneTag: nil, latencyMS: nil, modelVersion: nil,
            probs: nil, scores: nil, tag: nil, code: nil, message: nil,
            request: nil, requestEncoding: nil, status: nil
        )
        let textFrame = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        let connection: URLSessionWebSocketTask
        if let socket {
            connection = socket
        } else {
            var request = URLRequest(url: try configuration.sessionURL())
            if let token = configuration.token, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            connection = session.webSocketTask(with: request)
            connection.maximumMessageSize = 100_000
            socket = connection
            connection.resume()
        }
        let timer = Task {
            do {
                try await Task.sleep(for: .seconds(2))
                connection.cancel(with: .goingAway, reason: nil)
            } catch { /* Reply arrived before the deadline. */ }
        }
        defer { timer.cancel() }
        do {
            let reply = try await withTaskCancellationHandler {
                try await connection.send(.string(textFrame))
                return try await connection.receive()
            } onCancel: {
                connection.cancel(with: .goingAway, reason: nil)
            }
            guard case .string(let text) = reply else { throw ASRClientError.unavailable }
            let result = try JSONDecoder().decode(Events.self, from: Data(text.utf8))
            return try Self.validate(result, sessionID: configuration.sessionID,
                                     captionID: captionID, tStart: tStart, tEnd: tEnd)
        } catch {
            connection.cancel(with: .goingAway, reason: nil)
            if socket === connection { socket = nil }
            throw error
        }
    }

    static func validate(_ result: Events, sessionID: String, captionID: UUID,
                         tStart: Double, tEnd: Double) throws -> (String, String) {
        guard result.type == .asrResult, result.sessionID == sessionID,
              result.captionID.flatMap(UUID.init(uuidString:)) == captionID,
              let start = result.tStart, let end = result.tEnd,
              abs(start - tStart) < 0.000001, abs(end - tEnd) < 0.000001,
              result.status == .ok, let text = result.text, text.count <= 16_000,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let model = result.modelVersion, !model.isEmpty,
              let latency = result.latencyMS?["recv_to_send"], latency.isFinite, latency >= 0 else { throw ASRClientError.unavailable }
        return (text, model)
    }
}
