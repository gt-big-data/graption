import Foundation

/// Keeps local WhisperKit ready and returns only one result for each segment.
public struct FallbackCaptionTranscriber: CaptionTranscriber {
    private let remote: any CaptionTranscriber
    private let local: any CaptionTranscriber

    public init(remote: any CaptionTranscriber, local: any CaptionTranscriber) {
        self.remote = remote
        self.local = local
    }

    public func prepare(allowDownload: Bool) async throws {
        try await local.prepare(allowDownload: allowDownload)
    }

    public func transcribe(_ segment: AudioSegment) async throws -> TranscriptionResult {
        do {
            let result = try await remote.transcribe(segment)
            try Task.checkCancellation()
            if result.captionID == segment.captionID,
               result.tStart == segment.tStart, result.tEnd == segment.tEnd,
               !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return result
            }
        } catch {
            try Task.checkCancellation()
        }
        return try await local.transcribe(segment)
    }
}
