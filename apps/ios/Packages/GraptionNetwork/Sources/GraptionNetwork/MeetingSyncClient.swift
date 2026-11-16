import Foundation
import GraptionCore

/// Local session files are the durable upload queue. Retries upsert by session UUID.
public actor MeetingSyncClient {
    private var uploaded: [UUID: Data] = [:]

    public init() {}

    public func sync(store: any SessionStore, configuration: ToneClientConfiguration) async throws {
        guard ["ws", "wss"].contains(configuration.serverURL.scheme ?? "") else {
            throw ToneClientError.invalidServerURL
        }
        var components = URLComponents(url: configuration.serverURL, resolvingAgainstBaseURL: false)
        components?.scheme = configuration.serverURL.scheme == "wss" ? "https" : "http"
        let base = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        components?.path = "/" + ([base, "api/meetings"].filter { !$0.isEmpty }.joined(separator: "/"))
        components?.query = nil
        components?.fragment = nil
        guard let url = components?.url else { throw ToneClientError.invalidServerURL }
        for session in try await store.loadSyncSessions() {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let fingerprint = try encoder.encode(session)
            guard uploaded[session.id] != fingerprint else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = configuration.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try SessionExport.encode([session])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            uploaded[session.id] = fingerprint
        }
    }
}
