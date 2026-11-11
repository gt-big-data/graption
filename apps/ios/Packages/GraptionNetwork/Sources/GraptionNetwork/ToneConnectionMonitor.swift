import Combine
import Foundation

/// App-facing tone connection. Receives delayed tags independently of caption rendering
/// and retries quietly after failures.
@MainActor
public final class ToneConnectionMonitor: ObservableObject {
    public enum State: Equatable, Sendable {
        case disabled
        case connecting
        case connected
        case retrying

        public var label: String {
            switch self {
            case .disabled: "Tone server: off"
            case .connecting: "Tone server: connecting…"
            case .connected: "Tone server: connected"
            case .retrying: "Tone server: unavailable — retrying"
            }
        }
    }

    @Published public private(set) var state: State = .disabled

    public var onToneResult: ((String, String?) -> Void)?

    /// Drops audio while disconnected; never queues or stores recordings.
    public func send(captionID: String, tStart: Double, tEnd: Double, samples: [Float]) async {
        guard state == .connected, let client else { return }
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let finite = sample.isFinite ? Double(sample) : 0
            let value = Int16(max(-32768, min(32767, (finite * 32768).rounded())))
            let bits = UInt16(bitPattern: value)
            pcm.append(UInt8(bits & 255))
            pcm.append(UInt8(bits >> 8))
        }
        try? await client.sendToneRequest(captionID: captionID, tStart: tStart,
            tEnd: tEnd, sampleRate: 16_000, pcm16: pcm)
    }

    private let client: ToneClient?
    private var monitorTask: Task<Void, Never>?

    public init(configuration: ToneClientConfiguration?) {
        self.client = configuration.map { ToneClient(configuration: $0) }
    }

    public func start() {
        guard monitorTask == nil, let client else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.monitor(client: client)
        }
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        state = .disabled
    }

    private func monitor(client: ToneClient) async {
        while !Task.isCancelled {
            state = .connecting
            do {
                try await client.connect()
                try await client.sendToneRequest(
                    captionID: UUID().uuidString,
                    tStart: 0,
                    tEnd: 0,
                    sampleRate: 16_000,
                    pcm16: Data([0, 0])
                )
                _ = try await client.receiveNext()
                state = .connected

                while !Task.isCancelled {
                    let reply = try await client.receiveNext()
                    if case .toneResult(let event) = reply, let id = event.captionID {
                        onToneResult?(id, event.tag)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                await client.disconnect()
                state = .retrying
                try? await Task.sleep(for: ToneClient.reconnectDelay)
            }
        }
        await client.disconnect()
    }
}
