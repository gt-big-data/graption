import Foundation
import Security

public struct MacPairing: Codable, Sendable {
    public let serverURL: URL
    private let token: String
    private let asrToken: String?

    private struct Code: Decodable, Sendable {
        let v: Int
        let url: URL
        let code: String
    }

    private struct Reply: Decodable, Sendable {
        let token: String
        let asr_token: String?
    }

    private static let service = "Graption.MacPairing"
    private static let account = "paired-server"

    public func toneConfiguration(sessionID: String) -> ToneClientConfiguration {
        ToneClientConfiguration(serverURL: serverURL, sessionID: sessionID, token: token)
    }

    public var asrConfiguration: ASRClientConfiguration? {
        asrToken.map { ASRClientConfiguration(serverURL: serverURL, token: $0) }
    }

    public static func connect(scannedText: String) async throws -> Self {
        guard let code = try? JSONDecoder().decode(Code.self, from: Data(scannedText.utf8)),
              code.v == 1, (16...100).contains(code.code.count),
              var parts = URLComponents(url: code.url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty,
              parts.scheme == "wss" || (parts.scheme == "ws" && host.lowercased().hasSuffix(".local")),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw PairingError.invalidCode
        }
        parts.scheme = parts.scheme == "wss" ? "https" : "http"
        parts.path = "/api/pairing/connect"
        guard let url = parts.url else { throw PairingError.invalidCode }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code.code])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              !reply.token.isEmpty else {
            throw PairingError.rejected
        }
        let pairing = Self(serverURL: code.url, token: reply.token, asrToken: reply.asr_token)
        try pairing.save()
        return pairing
    }

    public static func load() -> Self? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func save() throws {
        let data = try JSONEncoder().encode(self)
        let query = Self.keychainQuery
        var status = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PairingError.couldNotSave }
    }

    private enum PairingError: LocalizedError {
        case invalidCode, rejected, couldNotSave

        var errorDescription: String? {
            switch self {
            case .invalidCode: "Scan a Graption pairing QR code from the Mac dashboard."
            case .rejected: "The code expired or was already used. Show a new QR code on the Mac."
            case .couldNotSave: "This device could not save the Mac connection."
            }
        }
    }
}
