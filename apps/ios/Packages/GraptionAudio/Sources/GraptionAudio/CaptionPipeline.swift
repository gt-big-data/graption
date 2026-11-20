import Foundation

/// Main-actor queue ownership keeps microphone callbacks and UI delivery simple.
/// Awaiting the transcriber yields the main actor while model work runs elsewhere.
@MainActor
public final class CaptionPipeline {
    public struct Delivery {
        public let result: TranscriptionResult
        /// The finalized VAD segment that produced `result`.
        public let segment: AudioSegment
        public let transcriptionSeconds: TimeInterval
        public let receivedAt: ContinuousClock.Instant
    }

    public private(set) var isReady = false
    public private(set) var isPreparing = false
    public var onResult: ((Delivery) -> Void)?
    /// Provisional results for in-progress segments, delivered on
    /// `onPartialResult` instead: the same caption ID arrives again as a
    /// final on `onResult` when the segment ends.
    public var onPartialResult: ((Delivery) -> Void)?
    public var onError: ((UUID?, Error) -> Void)?

    private let transcriber: any CaptionTranscriber
    private let maxPendingSegments: Int
    private var pending: [(AudioSegment, ContinuousClock.Instant)] = []
    private var isProcessing = false
    private var generation = 0
    /// Latest-only partial lane: a newer snapshot supersedes an unstarted
    /// or in-flight stale one, so partials never queue up behind finals.
    private var latestPartial: AudioSegment?
    private var isPartialProcessing = false

    public init(transcriber: any CaptionTranscriber = WhisperKitTranscriber(),
                maxPendingSegments: Int = 8) {
        precondition(maxPendingSegments > 0)
        self.transcriber = transcriber
        self.maxPendingSegments = maxPendingSegments
    }

    public func prepare(allowDownload: Bool = false) async throws {
        guard !isReady, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        try await transcriber.prepare(allowDownload: allowDownload)
        isReady = true
    }

    public func enqueue(_ segment: AudioSegment) {
        guard isReady else {
            onError?(segment.captionID, TranscriberError.modelNotReady)
            return
        }
        guard pending.count < maxPendingSegments else {
            onError?(segment.captionID, PipelineError.queueFull)
            return
        }
        pending.append((segment, ContinuousClock.now))
        guard !isProcessing else { return }
        isProcessing = true
        Task { await drain() }
    }

    /// Queue a provisional snapshot of a still-growing segment. Only the
    /// newest snapshot matters; stale ones are dropped, never queued.
    public func enqueuePartial(_ segment: AudioSegment) {
        guard isReady else { return }
        latestPartial = segment
        guard !isPartialProcessing else { return }
        isPartialProcessing = true
        Task { await drainPartials() }
    }

    private func drainPartials() async {
        defer { isPartialProcessing = false }
        while let segment = latestPartial {
            latestPartial = nil
            let session = generation
            let started = ContinuousClock.now
            let receivedAt = ContinuousClock.now
            do {
                let result = try await transcriber.transcribe(segment)
                guard session == generation else { return }
                // A newer snapshot arrived mid-transcription: this text is
                // already stale, so skip delivery and take the newer one.
                guard latestPartial == nil else { continue }
                onPartialResult?(Delivery(result: result,
                                          segment: segment,
                                          transcriptionSeconds: Self.seconds(started.duration(to: .now)),
                                          receivedAt: receivedAt))
            } catch {
                // Partials are best-effort; the final segment still follows.
                guard session == generation else { return }
            }
        }
    }

    /// Discard queued work and suppress an old session's in-flight result.
    public func reset() {
        generation += 1
        pending.removeAll()
        latestPartial = nil
    }

    private func drain() async {
        defer { isProcessing = false }
        while !pending.isEmpty {
            let (segment, receivedAt) = pending.removeFirst()
            let session = generation
            let started = ContinuousClock.now
            do {
                let result = try await transcriber.transcribe(segment)
                guard session == generation else { continue }
                onResult?(Delivery(result: result,
                                   segment: segment,
                                   transcriptionSeconds: Self.seconds(started.duration(to: .now)),
                                   receivedAt: receivedAt))
            } catch {
                guard session == generation else { continue }
                onError?(segment.captionID, error)
            }
        }
    }

    public static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

public enum PipelineError: LocalizedError {
    case queueFull
    public var errorDescription: String? {
        "Caption queue is full; this segment was dropped."
    }
}
